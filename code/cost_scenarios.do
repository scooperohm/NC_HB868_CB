* =============================================================================
* cost_scenarios.do
*
* SCENARIOS (probability / cost / sentence assumption sets, borrowed from
* varying_cost_and_p_assumptions.do):
*   baseline       LOW probs,  LOW costs,  LOW sentence   (document floor)
*   prob_high      HIGH probs, LOW costs,  LOW sentence
*   cost_high      LOW probs,  HIGH costs, LOW sentence
*   sentence_high  LOW probs,  LOW costs,  HIGH sentence
*   all_avg        MID probs,  MID costs,  MID sentence
*
* The colorimetric multipliers (p_use, false-positive rate, tests/arrest, test
* cost) are held fixed at their main.do values across all scenarios -- consistent
* with the document's first four scenarios, which vary only one of
* probs/costs/sentence at a time.
*
* Pipeline requirement: nibrs_data_cleaned.dta (output of classify_sentences.do,
* one row per arrested person) plus the three lookup .dta files built by
* sentence_lengths.do. Runs after estimate_costs.do.
* =============================================================================

* Colorimetric multipliers -- held fixed across scenarios. Inherited from
* params.do when run in the pipeline; defaulted here for standalone runs.
if "$proportion_colormetric_use"   == "" global proportion_colormetric_use   .499
if "$colormetric_error_rate"       == "" global colormetric_error_rate       .037
if "$colormetric_tests_per_arrest" == "" global colormetric_tests_per_arrest 1.2
if "$c_colormetric"                == "" global c_colormetric                 2


* -----------------------------------------------------------------------------
* PROGRAMS: probability assumption sets (Baltimore JHU Table 1)
* -----------------------------------------------------------------------------
capture program drop set_low_probs
program set_low_probs
    global p_booking 0.95
    global p_arraignment 1.00
    global p_pre_trial 0.95
    global p_bail_review 1.00
    global p_dismissed_after_bail_review 0.05
    global p_released 0.90
    global p_home_confinement 0.05
    global p_held_in_custody 0.05
    global p_case_preperation 1.00
    global p_charges_dismissed 0.66
    global p_case_presentation 0.34
    global p_sent_outcome_wo_cost 0.62
end

capture program drop set_high_probs
program set_high_probs
    global p_booking 0.99
    global p_arraignment 1.00
    global p_pre_trial 0.99
    global p_bail_review 1.00
    global p_dismissed_after_bail_review 0.01
    global p_released 0.80
    global p_home_confinement 0.10
    global p_held_in_custody 0.10
    global p_case_preperation 1.00
    global p_charges_dismissed 0.40
    global p_case_presentation 0.60
    global p_sent_outcome_wo_cost 0.40
end

capture program drop set_avg_probs
program set_avg_probs
    global p_booking 0.97
    global p_arraignment 1.00
    global p_pre_trial 0.97
    global p_bail_review 1.00
    global p_dismissed_after_bail_review 0.03
    global p_released 0.85
    global p_home_confinement 0.075
    global p_held_in_custody 0.075
    global p_case_preperation 1.00
    global p_charges_dismissed 0.53
    global p_case_presentation 0.47
    global p_sent_outcome_wo_cost 0.51
end


* -----------------------------------------------------------------------------
* PROGRAMS: cost assumption sets (Baltimore JHU Table 1)
* -----------------------------------------------------------------------------
capture program drop set_low_costs
program set_low_costs
    global c_arrest 54
    global c_booking 226
    global c_pre_trial 76
    global c_held_in_custody 1847
    global c_case_preparation 1117
    global c_case_outcome 170
    global c_probation_visit 13
    global c_prison 48156
end

capture program drop set_high_costs
program set_high_costs
    global c_arrest 186
    global c_booking 684
    global c_pre_trial 197
    global c_held_in_custody 3958
    global c_case_preparation 3651
    global c_case_outcome 879
    global c_probation_visit 59
    global c_prison 48156
end

capture program drop set_avg_costs
program set_avg_costs
    global c_arrest 120
    global c_booking 455
    global c_pre_trial 136.5
    global c_held_in_custody 2902.5
    global c_case_preparation 2384
    global c_case_outcome 524.5
    global c_probation_visit 36
    global c_prison 48156
end


* -----------------------------------------------------------------------------
* PROGRAM: compute_arrest_costs
*
* Builds the per-arrest cost/waste dataset under the currently-set globals.
* Mirrors estimate_costs.do, but (a) selects sentence/probation length columns
* from $g_sent_choice / $g_prob_choice, (b) collapses to one row per ARRESTED
* PERSON keeping `year`, and (c) computes waste_per_arrest and drug_bucket.
*
*   $g_sent_choice  "low" | "high" | "avg"      (active-sentence length)
*   $g_prob_choice  "min" | "max" | "expected"  (probation length column)
*
* Leaves in memory: year, unique_incident_id, arrestee_sequence_number,
* drug_category, drug_bucket, expected_cost_per_arrest, waste_per_arrest.
* -----------------------------------------------------------------------------
capture program drop compute_arrest_costs
program compute_arrest_costs

    use "$directory\data\nibrs_data_cleaned.dta", clear

    rename highest_charge charge_class
    joinby charge_class using "$directory\data\empirical_sentence_lookup.dta", unmatched(master)

    merge m:1 charge_class drug_category using "$directory\data\trafficking_sentence_lookup.dta", ///
        keep(master match) keepusing(min_months max_months) nogen

    * --- Active-sentence length column ---
    gen double _smin = avg_min_mo
    gen double _smax = avg_max_mo
    replace _smin = min_months if trafficking == 1
    replace _smax = max_months if trafficking == 1
    if "$g_sent_choice" == "low" {
        gen double sent_used = _smin
    }
    else if "$g_sent_choice" == "high" {
        gen double sent_used = _smax
    }
    else {
        gen double sent_used = (_smin + _smax) / 2
    }

    * Trafficking disposition override (statutory, PRL-independent)
    replace p_community    = 0 if trafficking == 1
    replace p_intermediate = 0 if trafficking == 1
    replace p_active       = 1 if trafficking == 1

    * Defensive missing handling for unmatched charge classes
    replace prl_weight = 1 if missing(prl_weight)
    foreach v in p_community p_intermediate p_active sent_used {
        replace `v' = 0 if missing(`v')
    }

    * --- Probation length column ($g_prob_choice) for C and I dispositions ---
    gen str8 offense_level = cond(substr(charge_class,1,6)=="Felony", "felony", "misd")
    local probcol "prob_${g_prob_choice}_months"
    preserve
        use "$directory\data\probation_length_lookup.dta", clear
        keep if disposition == "C"
        rename `probcol' prob_months_comm
        keep offense_level prob_months_comm
        tempfile pc
        save `pc'
    restore
    preserve
        use "$directory\data\probation_length_lookup.dta", clear
        keep if disposition == "I"
        rename `probcol' prob_months_int
        keep offense_level prob_months_int
        tempfile pi
        save `pi'
    restore
    merge m:1 offense_level using `pc', keep(master match) nogen
    merge m:1 offense_level using `pi', keep(master match) nogen
    replace prob_months_comm = 0 if missing(prob_months_comm)
    replace prob_months_int  = 0 if missing(prob_months_int)

    * --- Cumulative stage-reach probabilities ---
    local pra  = 1
    local prb  = `pra'  * $p_booking
    local prar = `prb'  * $p_arraignment
    local prpt = `prar' * $p_pre_trial
    local prbr = `prpt' * $p_bail_review
    local prbd = `prbr' * (1 - $p_dismissed_after_bail_review)
    local prcp = `prbd' * $p_case_preperation
    local prcs = `prcp' * $p_case_presentation
    local prco = `prcs' * (1 - $p_sent_outcome_wo_cost)

    * --- Per-row cost components (weighted by prl_weight, sums to 1/arrest) ---
    gen double c_pre_arrest    = prl_weight * `pra'  * $c_arrest
    gen double c_pre_booking   = prl_weight * `prb'  * $c_booking
    gen double c_pre_pretrial  = prl_weight * `prpt' * $c_pre_trial
    gen double c_pre_detention = prl_weight * `prbd' * $p_held_in_custody * $c_held_in_custody
    gen double c_pre_caseprep  = prl_weight * `prcp' * $c_case_preparation
    gen double c_pre_outcome   = prl_weight * `prcs' * $c_case_outcome

    gen double c_sent_active = prl_weight * `prco' * p_active       * sent_used        * ($c_prison / 12)
    gen double c_sent_int    = prl_weight * `prco' * p_intermediate * prob_months_int  * $c_probation_visit
    gen double c_sent_comm   = prl_weight * `prco' * p_community    * prob_months_comm * $c_probation_visit

    * --- Collapse PRL rows back to one row per arrested person (keep year) ---
    collapse (sum) c_pre_arrest c_pre_booking c_pre_pretrial c_pre_detention ///
                   c_pre_caseprep c_pre_outcome c_sent_active c_sent_int c_sent_comm ///
             (firstnm) drug_category, ///
             by(year unique_incident_id arrestee_sequence_number)

    gen double expected_cost_per_arrest = c_pre_arrest + c_pre_booking + c_pre_pretrial ///
                                        + c_pre_detention + c_pre_caseprep + c_pre_outcome ///
                                        + c_sent_active  + c_sent_int     + c_sent_comm

    * --- Colorimetric waste per arrest (multipliers held at params.do values) ---
    gen double waste_per_arrest = $proportion_colormetric_use ///
                                * $colormetric_error_rate ///
                                * (expected_cost_per_arrest ///
                                   + $proportion_colormetric_use * $colormetric_tests_per_arrest * $c_colormetric)

    * --- Drug bucket (FBI UCR taxonomy; the document's four categories) ---
    gen str20 drug_bucket = "other_nonnarcotic"
    replace drug_bucket = "marijuana"           if inlist(drug_category, "marijuana", "hashish")
    replace drug_bucket = "cocaine_opioids"     if inlist(drug_category, "cocaine", "heroin", "morphine", "opium")
    replace drug_bucket = "synthetic_narcotics" if inlist(drug_category, "other_narcotic", "hydromorphone", "fentanyl", "carfentanyl")
end


* =============================================================================
* (A)+(B)  Arrests and baseline cost per arrest, by drug type and year
* =============================================================================
* Arrest counts are assumption-independent; per-arrest cost uses the baseline
* (minimum) assumption set, matching the document's per-bucket cost figures.

set_low_probs
set_low_costs
global g_sent_choice "low"
global g_prob_choice "min"
compute_arrest_costs

* Number of years present in the data (for annualizing summed waste below)
quietly levelsof year, local(years)
local nyears : word count `years'

preserve
    gen long _one = 1
    collapse (sum)  n_arrests           = _one ///
             (mean) mean_cost_per_arrest = expected_cost_per_arrest ///
             (sum)  total_cost           = expected_cost_per_arrest ///
                    total_waste          = waste_per_arrest, ///
             by(year drug_bucket)

    label var n_arrests            "Drug arrests (NIBRS, NC)"
    label var mean_cost_per_arrest "Mean E[legal-system cost]/arrest, baseline ($)"
    label var total_cost           "Total E[legal-system cost], baseline ($)"
    label var total_waste          "Total colorimetric waste, baseline ($)"

    save "$directory\data\arrests_cost_by_type_year.dta", replace

    di as text ""
    di as text "===== (A) Arrests by drug type per year ====="
    tabdisp year drug_bucket, cell(n_arrests)

    di as text ""
    di as text "===== (B) Mean baseline cost per arrest by drug type per year ($) ====="
    tabdisp year drug_bucket, cell(mean_cost_per_arrest) format(%9.0f)
restore


* =============================================================================
* (C)  Annual colorimetric waste under each scenario
* =============================================================================
* For each scenario, recompute per-arrest waste, then sum waste_per_arrest over
* every arrest and divide by the number of years to annualize.

tempfile scenres
capture postclose scen_post
postfile scen_post str20 scenario str20 drug_bucket long n_arrests ///
    double mean_cost double total_waste double annual_waste ///
    using `scenres', replace

* Per-scenario, per-year waste -- feeds the cumulative cost-benefit time series
* exhibit built in make_exhibits.do.
tempfile yearres
capture postclose year_post
postfile year_post str20 scenario double year double total_waste long n_arrests ///
    using `yearres', replace

foreach s in baseline prob_high cost_high sentence_high all_avg {

    di as text ""
    di as text "Running scenario: `s'"

    if "`s'" == "baseline" {
        set_low_probs
        set_low_costs
        global g_sent_choice "low"
        global g_prob_choice "min"
    }
    else if "`s'" == "prob_high" {
        set_high_probs
        set_low_costs
        global g_sent_choice "low"
        global g_prob_choice "min"
    }
    else if "`s'" == "cost_high" {
        set_low_probs
        set_high_costs
        global g_sent_choice "low"
        global g_prob_choice "min"
    }
    else if "`s'" == "sentence_high" {
        set_low_probs
        set_low_costs
        global g_sent_choice "high"
        global g_prob_choice "max"
    }
    else if "`s'" == "all_avg" {
        set_avg_probs
        set_avg_costs
        global g_sent_choice "avg"
        global g_prob_choice "expected"
    }

    compute_arrest_costs

    * Overall (ALL drug types)
    quietly summ waste_per_arrest
    local tw = r(sum)
    local nn = r(N)
    quietly summ expected_cost_per_arrest
    post scen_post ("`s'") ("ALL") (`nn') (r(mean)) (`tw') (`tw'/`nyears')

    * By drug bucket
    foreach b in marijuana cocaine_opioids synthetic_narcotics other_nonnarcotic {
        quietly summ waste_per_arrest if drug_bucket == "`b'"
        local twb = r(sum)
        local nnb = r(N)
        quietly summ expected_cost_per_arrest if drug_bucket == "`b'"
        post scen_post ("`s'") ("`b'") (`nnb') (r(mean)) (`twb') (`twb'/`nyears')
    }

    * Per-year total waste (all drug types) under this scenario
    foreach yr of local years {
        quietly summ waste_per_arrest if year == `yr'
        post year_post ("`s'") (`yr') (r(sum)) (`r(N)')
    }
}

postclose scen_post
postclose year_post

* Save the per-scenario, per-year waste series for make_exhibits.do.
use `yearres', clear
label var scenario    "Assumption scenario"
label var year        "Year"
label var total_waste "Total colorimetric waste this year ($)"
label var n_arrests   "Arrests this year"
save "$directory\data\waste_by_scenario_year.dta", replace


* -----------------------------------------------------------------------------
* Present and save scenario results
* -----------------------------------------------------------------------------
use `scenres', clear

gen byte _ord = .
replace _ord = 1 if scenario == "baseline"
replace _ord = 2 if scenario == "prob_high"
replace _ord = 3 if scenario == "cost_high"
replace _ord = 4 if scenario == "sentence_high"
replace _ord = 5 if scenario == "all_avg"

gen byte _bord = .
replace _bord = 0 if drug_bucket == "ALL"
replace _bord = 1 if drug_bucket == "marijuana"
replace _bord = 2 if drug_bucket == "cocaine_opioids"
replace _bord = 3 if drug_bucket == "synthetic_narcotics"
replace _bord = 4 if drug_bucket == "other_nonnarcotic"

sort _ord _bord
drop _ord _bord

format mean_cost total_waste annual_waste %15.2fc
format n_arrests %12.0fc

label var scenario     "Assumption scenario"
label var drug_bucket  "Drug bucket"
label var n_arrests    "Arrests (all years in data)"
label var mean_cost    "Mean E[cost] per arrest ($)"
label var total_waste  "Total colorimetric waste over data period ($)"
label var annual_waste "Annual colorimetric waste ($)"

di as text ""
di as text "===== (C) Annual colorimetric waste by scenario (sum waste_per_arrest / `nyears' yr) ====="
list scenario drug_bucket n_arrests mean_cost annual_waste, sepby(scenario) noobs abbreviate(20)

save "$directory\data\waste_by_scenario.dta", replace

di as text ""
di as text "cost_scenarios.do complete."
di as text "Saved: arrests_cost_by_type_year.dta  (parts A & B)"
di as text "Saved: waste_by_scenario.dta          (part C)"
