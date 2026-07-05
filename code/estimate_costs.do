* =============================================================================
* estimate_costs.do
*
* Computes E[cost per drug arrest] for every arrest in nibrs_data.dta and
* the estimated financial loss attributable to colormetric false positives.
*
*
* COST CHAIN PER ARREST:
*   arrest -> booking -> arraignment -> pre-trial -> bail review ->
*   bond/detention -> case prep -> case presentation -> sentencing outcome
*
* Each stage's cost is incurred only with probability = product of stage
* probabilities up to that stage. The terminal sentence cost uses the SPAC
* empirical disposition mix per (charge_class, PRL) -- PRL is row-expanded
* via joinby and weighted by prl_weight = P(PRL | class) from FY 2024.
*
* COLORMETRIC WASTE PER ARREST:
*   waste = $proportion_colormetric_use
*         * $colormetric_error_rate
*         * ( expected_cost_per_arrest
*           + $colormetric_tests_per_arrest * $c_colormetric )
*
* Test cost is counted only on false-positive arrests.
* =============================================================================

use "$directory\data\nibrs_data_cleaned.dta", clear

* Sanity-check required columns produced by classify_sentences.do
foreach v in highest_charge trafficking drug_category unique_incident_id {
    capture confirm variable `v'
    if _rc {
        di as error "Required variable `v' not found -- run upstream do-files first."
        exit 111
    }
}

* -----------------------------------------------------------------------------
* MERGE: expand by PRL, attach disposition mix + sentence, trafficking
* override, probation lengths
* -----------------------------------------------------------------------------

rename highest_charge charge_class
joinby charge_class using "$directory\data\empirical_sentence_lookup.dta", unmatched(master)

merge m:1 charge_class drug_category using "$directory\data\trafficking_sentence_lookup.dta", ///
    keep(master match) keepusing(min_months max_months) nogen

* Override empirical mix with statutory mandatory for trafficking rows.
* Trafficking sentence is PRL-independent -> identical across the 6 expanded
* rows for that arrest; prl_weight still sums to 1 so the math holds.
* Fines are excluded: they are paid by the defendant to the state (fines 
* represent state "revenue", but profiting off prosecuting innocent people 
* should probably not be classified as a financial gain for the state). 
replace p_community    = 0           if trafficking == 1
replace p_intermediate = 0           if trafficking == 1
replace p_active       = 1           if trafficking == 1
replace avg_min_mo     = min_months  if trafficking == 1
replace avg_max_mo     = max_months  if trafficking == 1

* Defensive: arrests whose charge_class did not match the lookup keep one
* master row with no lookup columns -> zero out so they contribute only
* pre-conviction costs and don't propagate missingness.
replace prl_weight     = 1 if missing(prl_weight)
foreach v in p_community p_intermediate p_active avg_min_mo avg_max_mo {
    replace `v' = 0 if missing(`v')
}

* Attach probation lengths for both C and I dispositions
gen str8 offense_level = cond(substr(charge_class,1,6)=="Felony", "felony", "misd")
preserve
    use "$directory\data\probation_length_lookup.dta", clear
    keep if disposition == "C"
    rename prob_expected_months prob_months_comm
    keep offense_level prob_months_comm
    tempfile prob_c
    save `prob_c'
restore
preserve
    use "$directory\data\probation_length_lookup.dta", clear
    keep if disposition == "I"
    rename prob_expected_months prob_months_int
    keep offense_level prob_months_int
    tempfile prob_i
    save `prob_i'
restore
merge m:1 offense_level using `prob_c', keep(master match) nogen
merge m:1 offense_level using `prob_i', keep(master match) nogen
replace prob_months_comm = 0 if missing(prob_months_comm)
replace prob_months_int  = 0 if missing(prob_months_int)


* -----------------------------------------------------------------------------
* STAGE-REACH PROBABILITIES (cumulative, constant across observations)
* -----------------------------------------------------------------------------

local p_reach_arrest          = 1
local p_reach_booking         = `p_reach_arrest'      * $p_booking
local p_reach_arraignment     = `p_reach_booking'     * $p_arraignment
local p_reach_pretrial        = `p_reach_arraignment' * $p_pre_trial
local p_reach_bailreview      = `p_reach_pretrial'    * $p_bail_review
local p_reach_bond            = `p_reach_bailreview'  * (1 - $p_dismissed_after_bail_review)
local p_reach_caseprep        = `p_reach_bond'        * $p_case_preperation
local p_reach_casepres        = `p_reach_caseprep'    * $p_case_presentation
local p_reach_costed_outcome  = `p_reach_casepres'    * (1 - $p_sent_outcome_wo_cost)

di as text ""
di as text "===== Stage-reach probabilities ====="
di as text "  arrest        = " %5.3f `p_reach_arrest'
di as text "  booking       = " %5.3f `p_reach_booking'
di as text "  arraignment   = " %5.3f `p_reach_arraignment'
di as text "  pretrial      = " %5.3f `p_reach_pretrial'
di as text "  bail review   = " %5.3f `p_reach_bailreview'
di as text "  bond/detention= " %5.3f `p_reach_bond'
di as text "  case prep     = " %5.3f `p_reach_caseprep'
di as text "  case present  = " %5.3f `p_reach_casepres'
di as text "  costed outcome= " %5.3f `p_reach_costed_outcome'


* -----------------------------------------------------------------------------
* PER-ROW COST COMPONENTS (weighted by prl_weight; sums to 1 per arrest)
* -----------------------------------------------------------------------------

* Pre-conviction costs are constant across an arrest's PRL rows; weighting
* by prl_weight and summing recovers the constant. Stages with no defined
* cost in main.do (arraignment, bail review hearing itself) are absorbed
* into adjacent stages' costs.
gen double c_pre_arrest    = prl_weight * `p_reach_arrest'    * $c_arrest
gen double c_pre_booking   = prl_weight * `p_reach_booking'   * $c_booking
gen double c_pre_pretrial  = prl_weight * `p_reach_pretrial'  * $c_pre_trial
gen double c_pre_detention = prl_weight * `p_reach_bond'      * $p_held_in_custody * $c_held_in_custody
gen double c_pre_caseprep  = prl_weight * `p_reach_caseprep'  * $c_case_preparation
gen double c_pre_outcome   = prl_weight * `p_reach_casepres'  * $c_case_outcome

* Sentence costs apply ONLY at the costed-outcome stage. SPAC disposition
* mix (p_community/intermediate/active) gives the per-class breakdown;
* trafficking rows already overridden to 100% active with statutory length.
gen double c_sent_active = prl_weight * `p_reach_costed_outcome' * p_active        * avg_min_mo         * ($c_prison / 12)
gen double c_sent_int    = prl_weight * `p_reach_costed_outcome' * p_intermediate  * prob_months_int    * $c_probation_visit
gen double c_sent_comm   = prl_weight * `p_reach_costed_outcome' * p_community     * prob_months_comm   * $c_probation_visit

* Save the pre-collapse expanded file (one row per arrest x PRL) for audit.
save "$directory\data\arrest_costs_expanded.dta", replace


* -----------------------------------------------------------------------------
* COLLAPSE back to per-arrested-person (sum across PRL rows; prl_weight sums
* to 1). Keyed on year + incident + arrestee sequence so co-arrestees in the
* same incident stay distinct (one row per person arrested).
* -----------------------------------------------------------------------------

collapse (sum)    c_pre_arrest c_pre_booking c_pre_pretrial c_pre_detention ///
                  c_pre_caseprep c_pre_outcome ///
                  c_sent_active c_sent_int c_sent_comm ///
         (firstnm) charge_class trafficking drug_category, ///
         by(year unique_incident_id arrestee_sequence_number)

gen double expected_cost_per_arrest = c_pre_arrest + c_pre_booking + c_pre_pretrial ///
                                    + c_pre_detention + c_pre_caseprep + c_pre_outcome ///
                                    + c_sent_active  + c_sent_int   + c_sent_comm


* -----------------------------------------------------------------------------
* COLORMETRIC WASTE PER ARREST
* -----------------------------------------------------------------------------
* Test-cost-per-false-positive-arrest = colormetric_tests_per_arrest * c_colormetric.
* Total wasted per arrest = P(uses colormetric) * P(false positive) *
*                          (expected downstream cost + wasted test cost).

gen double waste_per_arrest = $proportion_colormetric_use ///
                             * $colormetric_error_rate ///
                             * (expected_cost_per_arrest ///
                                + $proportion_colormetric_use * $colormetric_tests_per_arrest * $c_colormetric)

label var expected_cost_per_arrest "E[justice-system cost per arrest, $]"
label var waste_per_arrest         "E[cost wasted on false-positive colormetric, $]"
label var c_pre_arrest    "E[arrest stage cost, $]"
label var c_pre_booking   "E[booking stage cost, $]"
label var c_pre_pretrial  "E[pretrial stage cost, $]"
label var c_pre_detention "E[detention stage cost, $]"
label var c_pre_caseprep  "E[case-prep stage cost, $]"
label var c_pre_outcome   "E[case-outcome stage cost, $]"
label var c_sent_active   "E[active-sentence (prison) cost, $]"
label var c_sent_int      "E[intermediate-disposition probation cost, $]"
label var c_sent_comm     "E[community-disposition probation cost, $]"

save "$directory\data\arrest_costs.dta", replace


* -----------------------------------------------------------------------------
* SUMMARY OUTPUT
* -----------------------------------------------------------------------------

di as text ""
di as text "===== Aggregate estimates ====="
quietly summ expected_cost_per_arrest
local n_arrests  = r(N)
local mean_cost  = r(mean)
local total_cost = r(sum)

quietly summ waste_per_arrest
local total_waste = r(sum)
local mean_waste  = r(mean)

di as text "Arrests analyzed:               " %12.0fc `n_arrests'
di as text "Mean E[cost] per arrest:        $" %15.2fc `mean_cost'
di as text "Total E[justice-system cost]:   $" %15.2fc `total_cost'
di as text ""
di as text "Mean E[waste] per arrest:       $" %15.2fc `mean_waste'
di as text "Total E[colormetric waste]:     $" %15.2fc `total_waste'
di as text "Waste as % of total cost:       " %5.2f 100 * `total_waste' / `total_cost' " %"

di as text ""
di as text "===== Per-charge-class breakdown (mean cost & waste, count) ====="
tabstat expected_cost_per_arrest waste_per_arrest, ///
    by(charge_class) stat(mean sum n) format(%12.2fc) longstub

di as text ""
di as text "===== Cost decomposition (mean per arrest) ====="
summ c_pre_arrest c_pre_booking c_pre_pretrial c_pre_detention ///
     c_pre_caseprep c_pre_outcome ///
     c_sent_active c_sent_int c_sent_comm, format

di as text ""
di as text "estimate_costs.do complete."
di as text "Per-arrest output: arrest_costs.dta"
di as text "Pre-collapse audit: arrest_costs_expanded.dta"
