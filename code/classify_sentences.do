* =============================================================================
* classify_sentences.do
*
* Turns the raw seized-drug property records into one NC criminal charge per
* arrested person. For each of the up to three drugs on an incident, this file:
*   1. Converts the reported quantity to a common unit (pounds for mass,
*      gallons for volume, dosage units otherwise).
*   2. Assigns an NC offense class (misdemeanor, felony, or trafficking) from
*      the drug type and weight per G.S. 90-95, flagging trafficking rows and
*      recording a normalized drug_category for the downstream sentence lookups.
*   3. Reduces each incident's three drug slots to a single highest_charge
*      (most severe class wins; trafficking wins ties), carrying that slot's
*      trafficking flag and drug_category along.
* Finally it collapses to one row per arrested person (year x incident x
* arrestee), keeping that person's most severe charge, and saves
* nibrs_data_cleaned.dta for estimate_costs.do / cost_scenarios.do.
*
* Runs after build_nc_drug_arrests.do; expects nc_drug_arrests_2019_2024 in
* memory. Trafficking classifications feed trafficking_sentence_lookup.dta.
* =============================================================================


* Schedule II, III, and IV globals (not including the drugs listed below, which have sentencing regulations that differ from general drug schedules)
global scheduleII "morphine"

global scheduleIII "barbiturates", ///
    "other depressants: glutethimide or doriden, methaqualone or quaalude, pentazocine or talwin, etc.", ///
    "other narcotics: codeine, demerol, dihydromorphinone or dilaudid, hydrocodone or percodan, methadone, etc.", ///
    "other stimulants: adipex, fastine and ionamin (derivatives of phentermine), benzedrine, didrex, methylphenidate or ritalin, phenmetrazine or preludin, tenuate, etc."

global scheduleIV "opium", ///
    "other drugs: antidepressants (elavil, triavil, tofranil, etc.), aromatic hydrocarbons, propoxyphene or darvon, tranquilizers (chlordiazepoxide or librium, diazepam or valium, etc.), etc."


forval i = 1/3 {
	gen weight_`i' = estimated_quantity_`i' + (est_quantity_fractional_1000th`i' / 1000)
	
	* Convert weight into pounds
	replace weight_`i' = weight_`i' * 0.00220462 if type_of_measurement_`i' == "gram"
	replace weight_`i' = weight_`i' * 2.20462 if type_of_measurement_`i' == "kilogram"
	replace weight_`i' = weight_`i' / 16 if type_of_measurement_`i' == "ounce"
	replace type_of_measurement_`i' = "pound" if inlist(type_of_measurement_`i', "gram", "kilogram", "ounce")
	
	* Convert volume into gallons
	replace weight_`i' = weight_`i' / 128 if type_of_measurement_`i' == "fluid ounce"
	replace weight_`i' = weight_`i' / 3.78541 if type_of_measurement_`i' == "liter"
	replace weight_`i' = weight_`i' / 3785.41 if type_of_measurement_`i' == "milliliter"
	replace type_of_measurement_`i' = "gallon" if inlist(type_of_measurement_`i', "fluid ounce", "liter", "milliliter")

}

keep if type_of_property_loss == "seized" & property_description == "drugs/narcotics"	
	

forval i = 1/3 {

    * initialize charge variable
    gen charge_`i' = ""

    * Trafficking flag and drug-category label, used downstream by
    * sentence_lengths.do to apply mandatory G.S. 90-95(h) penalties
    * instead of the empirical SS-grid distribution. trafficking_`i'=1
    * iff the charge was assigned via one of the weight-tier branches
    * below; drug_category_`i' is the normalized label matching
    * trafficking_sentence_lookup.dta.
    gen byte trafficking_`i' = 0
    gen str25 drug_category_`i' = ""

    * ------------------
    * Misdemeanors
    * ------------------
    replace charge_`i' = "Misdemeanor_3" if inlist(suspected_drug_type_`i', "marijuana", "hashish")

    replace charge_`i' = "Misdemeanor_2" if suspected_drug_type_`i' == "schedule V"

    replace charge_`i' = "Misdemeanor_1" if inlist(suspected_drug_type_`i', "$scheduleII", "$scheduleIII", "$scheduleIV")
    replace charge_`i' = "Misdemeanor_1" if suspected_drug_type_`i' == "marijuana" & weight_`i' > 0.5 & type_of_measurement_`i' == "pound"
    replace charge_`i' = "Misdemeanor_1" if suspected_drug_type_`i' == "hashish" & weight_`i' > (1/20) & type_of_measurement_`i' == "pound"

    * ------------------
    * Felonies
    * ------------------

    * Class I
    replace charge_`i' = "Felony_I" if inlist(suspected_drug_type_`i', "heroin", "lsd", "hallucinogen", "pcp", "other hallucinogens: bmda (white acid), dmt, mda, mdma, mescaline or peyote, psilocybin, stp, etc.")

replace charge_`i' = "Felony_I" if suspected_drug_type_`i' == "hydromorphone" ///
    & weight_`i' > 4 & type_of_measurement_`i' == "dosage unit/items (pills, etc.)"

replace charge_`i' = "Felony_I" if inlist(suspected_drug_type_`i', "$scheduleII", "$scheduleIII", "$scheduleIV") ///
    & weight_`i' > 100 & type_of_measurement_`i' == "dosage unit/items (pills, etc.)"

replace charge_`i' = "Felony_I" if inlist(suspected_drug_type_`i', "amphetamines/methamphetamines", "fentanyl", "carfentanyl", ///
    "cocaine (all forms except crack)", "crack cocaine")

replace charge_`i' = "Felony_I" if suspected_drug_type_`i' == "hashish" ///
    & weight_`i' > (3/20) & type_of_measurement_`i' == "pound"

* -----------------------------------------------------------------------------
* TRAFFICKING BRANCHES (G.S. 90-95(h))
* Each block also sets trafficking_`i'=1 and drug_category_`i'.
* Mandatory minimums apply -- sentence_lengths.do overrides the
* empirical SS-grid distribution for these rows.
* -----------------------------------------------------------------------------

* Class H -- marijuana 10-50 lbs (90-95(h)(1) Tier 1)
replace charge_`i' = "Felony_H" if suspected_drug_type_`i' == "marijuana" ///
    & weight_`i' >= 10 & weight_`i' < 50 & type_of_measurement_`i' == "pound"
replace trafficking_`i'   = 1           if suspected_drug_type_`i' == "marijuana" ///
    & weight_`i' >= 10 & weight_`i' < 50 & type_of_measurement_`i' == "pound"
replace drug_category_`i' = "marijuana" if suspected_drug_type_`i' == "marijuana" ///
    & weight_`i' >= 10 & weight_`i' < 50 & type_of_measurement_`i' == "pound"

* Class G -- marijuana 50-2000 lbs (90-95(h)(1) Tier 2)
replace charge_`i' = "Felony_G" if suspected_drug_type_`i' == "marijuana" ///
    & inrange(weight_`i', 50, 2000) & type_of_measurement_`i' == "pound"
replace trafficking_`i'   = 1           if suspected_drug_type_`i' == "marijuana" ///
    & inrange(weight_`i', 50, 2000) & type_of_measurement_`i' == "pound"
replace drug_category_`i' = "marijuana" if suspected_drug_type_`i' == "marijuana" ///
    & inrange(weight_`i', 50, 2000) & type_of_measurement_`i' == "pound"

* Class G -- cocaine 28-200 g (90-95(h)(3) Tier 1)
replace charge_`i' = "Felony_G" if inlist(suspected_drug_type_`i', "cocaine (all forms except crack)", "crack cocaine") ///
    & inrange(weight_`i', 28/453.59237, 200/453.59237) & type_of_measurement_`i' == "pound"
replace trafficking_`i'   = 1         if inlist(suspected_drug_type_`i', "cocaine (all forms except crack)", "crack cocaine") ///
    & inrange(weight_`i', 28/453.59237, 200/453.59237) & type_of_measurement_`i' == "pound"
replace drug_category_`i' = "cocaine" if inlist(suspected_drug_type_`i', "cocaine (all forms except crack)", "crack cocaine") ///
    & inrange(weight_`i', 28/453.59237, 200/453.59237) & type_of_measurement_`i' == "pound"

* Class G -- LSD 100-500 dosage units (90-95(h)(4a) Tier 1)
replace charge_`i' = "Felony_G" if suspected_drug_type_`i' == "lsd" ///
    & weight_`i' >= 100 & weight_`i' < 500 & type_of_measurement_`i' == "dosage unit/items (pills, etc.)"
replace trafficking_`i'   = 1     if suspected_drug_type_`i' == "lsd" ///
    & weight_`i' >= 100 & weight_`i' < 500 & type_of_measurement_`i' == "dosage unit/items (pills, etc.)"
replace drug_category_`i' = "lsd" if suspected_drug_type_`i' == "lsd" ///
    & weight_`i' >= 100 & weight_`i' < 500 & type_of_measurement_`i' == "dosage unit/items (pills, etc.)"

* Class F -- marijuana 2000-10000 lbs (90-95(h)(1) Tier 3)
replace charge_`i' = "Felony_F" if suspected_drug_type_`i' == "marijuana" ///
    & inrange(weight_`i', 2000, 10000) & type_of_measurement_`i' == "pound"
replace trafficking_`i'   = 1           if suspected_drug_type_`i' == "marijuana" ///
    & inrange(weight_`i', 2000, 10000) & type_of_measurement_`i' == "pound"
replace drug_category_`i' = "marijuana" if suspected_drug_type_`i' == "marijuana" ///
    & inrange(weight_`i', 2000, 10000) & type_of_measurement_`i' == "pound"

* Class F -- cocaine 200-400 g (90-95(h)(3) Tier 2)
replace charge_`i' = "Felony_F" if inlist(suspected_drug_type_`i', "cocaine (all forms except crack)", "crack cocaine") ///
    & inrange(weight_`i', 200/453.59237, 400/453.59237) & type_of_measurement_`i' == "pound"
replace trafficking_`i'   = 1         if inlist(suspected_drug_type_`i', "cocaine (all forms except crack)", "crack cocaine") ///
    & inrange(weight_`i', 200/453.59237, 400/453.59237) & type_of_measurement_`i' == "pound"
replace drug_category_`i' = "cocaine" if inlist(suspected_drug_type_`i', "cocaine (all forms except crack)", "crack cocaine") ///
    & inrange(weight_`i', 200/453.59237, 400/453.59237) & type_of_measurement_`i' == "pound"

* Class H -- amphetamine 28-200 g (90-95(h)(3c) Tier 1).
* Note: NIBRS lumps amphetamines/methamphetamines into one type. We apply
* the AMPHETAMINE trafficking schedule (lighter than methamphetamine -- see
* 90-95(h)(3b) vs (3c)) as the conservative choice for the cost model:
* lower assigned class -> lower expected sentence -> lower estimated cost.
replace charge_`i' = "Felony_H" if suspected_drug_type_`i' == "amphetamines/methamphetamines" ///
    & inrange(weight_`i', 28/453.59237, 200/453.59237) & type_of_measurement_`i' == "pound"
replace trafficking_`i'   = 1             if suspected_drug_type_`i' == "amphetamines/methamphetamines" ///
    & inrange(weight_`i', 28/453.59237, 200/453.59237) & type_of_measurement_`i' == "pound"
replace drug_category_`i' = "amphetamine" if suspected_drug_type_`i' == "amphetamines/methamphetamines" ///
    & inrange(weight_`i', 28/453.59237, 200/453.59237) & type_of_measurement_`i' == "pound"

* Class F -- opioids 4-14 g (90-95(h)(4) Tier 1)
replace charge_`i' = "Felony_F" if suspected_drug_type_`i' == "opioids" ///
    & inrange(weight_`i', 4/453.59237, 14/453.59237) & type_of_measurement_`i' == "pound"
replace trafficking_`i'   = 1        if suspected_drug_type_`i' == "opioids" ///
    & inrange(weight_`i', 4/453.59237, 14/453.59237) & type_of_measurement_`i' == "pound"
replace drug_category_`i' = "opioid" if suspected_drug_type_`i' == "opioids" ///
    & inrange(weight_`i', 4/453.59237, 14/453.59237) & type_of_measurement_`i' == "pound"

* Class F -- LSD 500-1000 dosage units (90-95(h)(4a) Tier 2)
replace charge_`i' = "Felony_F" if suspected_drug_type_`i' == "lsd" ///
    & weight_`i' >= 500 & weight_`i' < 1000 & type_of_measurement_`i' == "dosage unit/items (pills, etc.)"
replace trafficking_`i'   = 1     if suspected_drug_type_`i' == "lsd" ///
    & weight_`i' >= 500 & weight_`i' < 1000 & type_of_measurement_`i' == "dosage unit/items (pills, etc.)"
replace drug_category_`i' = "lsd" if suspected_drug_type_`i' == "lsd" ///
    & weight_`i' >= 500 & weight_`i' < 1000 & type_of_measurement_`i' == "dosage unit/items (pills, etc.)"

* Class G -- amphetamine 200-400 g (90-95(h)(3c) Tier 2).
* Conservative: amphetamine schedule, not methamphetamine. See Class H note above.
replace charge_`i' = "Felony_G" if suspected_drug_type_`i' == "amphetamines/methamphetamines" ///
    & inrange(weight_`i', 200/453.59237, 400/453.59237) & type_of_measurement_`i' == "pound"
replace trafficking_`i'   = 1             if suspected_drug_type_`i' == "amphetamines/methamphetamines" ///
    & inrange(weight_`i', 200/453.59237, 400/453.59237) & type_of_measurement_`i' == "pound"
replace drug_category_`i' = "amphetamine" if suspected_drug_type_`i' == "amphetamines/methamphetamines" ///
    & inrange(weight_`i', 200/453.59237, 400/453.59237) & type_of_measurement_`i' == "pound"

* Class E -- opioids 14-28 g (90-95(h)(4) Tier 2)
replace charge_`i' = "Felony_E" if suspected_drug_type_`i' == "opioids" ///
    & inrange(weight_`i', 14/453.59237, 28/453.59237) & type_of_measurement_`i' == "pound"
replace trafficking_`i'   = 1        if suspected_drug_type_`i' == "opioids" ///
    & inrange(weight_`i', 14/453.59237, 28/453.59237) & type_of_measurement_`i' == "pound"
replace drug_category_`i' = "opioid" if suspected_drug_type_`i' == "opioids" ///
    & inrange(weight_`i', 14/453.59237, 28/453.59237) & type_of_measurement_`i' == "pound"

* Class D -- marijuana 10000+ lbs (90-95(h)(1) Tier 4)
replace charge_`i' = "Felony_D" if suspected_drug_type_`i' == "marijuana" ///
    & weight_`i' >= 10000 & type_of_measurement_`i' == "pound"
replace trafficking_`i'   = 1           if suspected_drug_type_`i' == "marijuana" ///
    & weight_`i' >= 10000 & type_of_measurement_`i' == "pound"
replace drug_category_`i' = "marijuana" if suspected_drug_type_`i' == "marijuana" ///
    & weight_`i' >= 10000 & type_of_measurement_`i' == "pound"

* Class D -- cocaine 400+ g (90-95(h)(3) Tier 3)
replace charge_`i' = "Felony_D" if inlist(suspected_drug_type_`i', "cocaine (all forms except crack)", "crack cocaine") ///
    & weight_`i' >= 400/453.59237 & type_of_measurement_`i' == "pound"
replace trafficking_`i'   = 1         if inlist(suspected_drug_type_`i', "cocaine (all forms except crack)", "crack cocaine") ///
    & weight_`i' >= 400/453.59237 & type_of_measurement_`i' == "pound"
replace drug_category_`i' = "cocaine" if inlist(suspected_drug_type_`i', "cocaine (all forms except crack)", "crack cocaine") ///
    & weight_`i' >= 400/453.59237 & type_of_measurement_`i' == "pound"

* Class D -- LSD 1000+ dosage units (90-95(h)(4a) Tier 3)
replace charge_`i' = "Felony_D" if suspected_drug_type_`i' == "lsd" ///
    & weight_`i' >= 1000 & type_of_measurement_`i' == "dosage unit/items (pills, etc.)"
replace trafficking_`i'   = 1     if suspected_drug_type_`i' == "lsd" ///
    & weight_`i' >= 1000 & type_of_measurement_`i' == "dosage unit/items (pills, etc.)"
replace drug_category_`i' = "lsd" if suspected_drug_type_`i' == "lsd" ///
    & weight_`i' >= 1000 & type_of_measurement_`i' == "dosage unit/items (pills, etc.)"

* Class E -- amphetamine 400+ g (90-95(h)(3c) Tier 3).
* Conservative: amphetamine schedule, not methamphetamine. See Class H note above.
replace charge_`i' = "Felony_E" if suspected_drug_type_`i' == "amphetamines/methamphetamines" ///
    & weight_`i' >= 400/453.59237 & type_of_measurement_`i' == "pound"
replace trafficking_`i'   = 1             if suspected_drug_type_`i' == "amphetamines/methamphetamines" ///
    & weight_`i' >= 400/453.59237 & type_of_measurement_`i' == "pound"
replace drug_category_`i' = "amphetamine" if suspected_drug_type_`i' == "amphetamines/methamphetamines" ///
    & weight_`i' >= 400/453.59237 & type_of_measurement_`i' == "pound"

* Class C -- opioids 28+ g (90-95(h)(4) Tier 3)
replace charge_`i' = "Felony_C" if suspected_drug_type_`i' == "opioids" ///
    & weight_`i' >= 28/453.59237 & type_of_measurement_`i' == "pound"
replace trafficking_`i'   = 1        if suspected_drug_type_`i' == "opioids" ///
    & weight_`i' >= 28/453.59237 & type_of_measurement_`i' == "pound"
replace drug_category_`i' = "opioid" if suspected_drug_type_`i' == "opioids" ///
    & weight_`i' >= 28/453.59237 & type_of_measurement_`i' == "pound"


	replace charge_`i' = "Unknown_drug" if suspected_drug_type_`i' == "unknown type drug" //If the officer doesn't report knowing a drug type, we can safely say that the arrest was the result of a false positive colormetric test (which would provide a drug type).

* -----------------------------------------------------------------------------
* Default drug_category mapping for all NIBRS suspected_drug_type values.
* Trafficking branches above already set drug_category_`i' for trafficking
* arrests (marijuana, cocaine, amphetamine, opioid, lsd). The `== ""` guard
* preserves those values; this block fills in non-trafficking arrests so
* drug_category is populated for every row downstream.
* -----------------------------------------------------------------------------
replace drug_category_`i' = "marijuana"          if drug_category_`i' == "" & suspected_drug_type_`i' == "marijuana"
replace drug_category_`i' = "hashish"            if drug_category_`i' == "" & suspected_drug_type_`i' == "hashish"
replace drug_category_`i' = "cocaine"            if drug_category_`i' == "" & inlist(suspected_drug_type_`i', "cocaine (all forms except crack)", "crack cocaine")
replace drug_category_`i' = "heroin"             if drug_category_`i' == "" & suspected_drug_type_`i' == "heroin"
replace drug_category_`i' = "opioid"             if drug_category_`i' == "" & suspected_drug_type_`i' == "opioids"
replace drug_category_`i' = "hydromorphone"      if drug_category_`i' == "" & suspected_drug_type_`i' == "hydromorphone"
replace drug_category_`i' = "fentanyl"           if drug_category_`i' == "" & suspected_drug_type_`i' == "fentanyl"
replace drug_category_`i' = "carfentanyl"        if drug_category_`i' == "" & suspected_drug_type_`i' == "carfentanyl"
replace drug_category_`i' = "amphetamine"        if drug_category_`i' == "" & suspected_drug_type_`i' == "amphetamines/methamphetamines"
replace drug_category_`i' = "lsd"                if drug_category_`i' == "" & suspected_drug_type_`i' == "lsd"
replace drug_category_`i' = "pcp"                if drug_category_`i' == "" & suspected_drug_type_`i' == "pcp"
replace drug_category_`i' = "hallucinogen"       if drug_category_`i' == "" & suspected_drug_type_`i' == "hallucinogen"
replace drug_category_`i' = "other_hallucinogen" if drug_category_`i' == "" & suspected_drug_type_`i' == "other hallucinogens: bmda (white acid), dmt, mda, mdma, mescaline or peyote, psilocybin, stp, etc."
replace drug_category_`i' = "schedule_v"         if drug_category_`i' == "" & suspected_drug_type_`i' == "schedule V"
replace drug_category_`i' = "morphine"           if drug_category_`i' == "" & suspected_drug_type_`i' == "morphine"
replace drug_category_`i' = "barbiturate"        if drug_category_`i' == "" & suspected_drug_type_`i' == "barbiturates"
replace drug_category_`i' = "other_depressant"   if drug_category_`i' == "" & suspected_drug_type_`i' == "other depressants: glutethimide or doriden, methaqualone or quaalude, pentazocine or talwin, etc."
replace drug_category_`i' = "other_narcotic"     if drug_category_`i' == "" & suspected_drug_type_`i' == "other narcotics: codeine, demerol, dihydromorphinone or dilaudid, hydrocodone or percodan, methadone, etc."
replace drug_category_`i' = "other_stimulant"    if drug_category_`i' == "" & suspected_drug_type_`i' == "other stimulants: adipex, fastine and ionamin (derivatives of phentermine), benzedrine, didrex, methylphenidate or ritalin, phenmetrazine or preludin, tenuate, etc."
replace drug_category_`i' = "opium"              if drug_category_`i' == "" & suspected_drug_type_`i' == "opium"
replace drug_category_`i' = "other_drug"         if drug_category_`i' == "" & suspected_drug_type_`i' == "other drugs: antidepressants (elavil, triavil, tofranil, etc.), aromatic hydrocarbons, propoxyphene or darvon, tranquilizers (chlordiazepoxide or librium, diazepam or valium, etc.), etc."
replace drug_category_`i' = "unknown"            if drug_category_`i' == "" & suspected_drug_type_`i' == "unknown type drug"
}

replace charge_1 = "Unknown_drug" if charge_1 == "" //the very few observations that do not have a drug listed


* Create a "highest charge" value. This will let us interpret all arrests
* as involving just one charge -- the single drug with the highest charge.
* The minimum assumption (vs the real world: one charge for a bag of cocaine,
* a second charge for the marijuana next to it, etc.)
*
* Iteration order: SEVERITY OUTSIDE, SLOT INSIDE. This guarantees the most
* severe charge across the three slots wins.
* The trafficking flag and drug_category from the slot driving the highest
* charge are propagated alongside.
gen highest_charge = ""
gen byte trafficking = 0
gen str25 drug_category = ""

foreach c in "Misdemeanor_3" "Misdemeanor_2" "Misdemeanor_1" ///
             "Felony_I" "Felony_H" "Felony_G" "Felony_F" "Felony_E" ///
             "Felony_D" "Felony_C" "Felony_B" "Felony_A" "Unknown_drug" {
    forvalues i = 1/3 {
        replace highest_charge  = "`c'"              if charge_`i' == "`c'"
        replace trafficking     = trafficking_`i'    if charge_`i' == "`c'"
        replace drug_category   = drug_category_`i'  if charge_`i' == "`c'"
    }
}

* Within the same severity tier, if any slot is trafficking, that slot's
* mandatory minimum dominates. Override to ensure trafficking wins ties.
foreach c in "Felony_H" "Felony_G" "Felony_F" "Felony_E" "Felony_D" "Felony_C" {
    forvalues i = 1/3 {
        replace trafficking   = 1                    if charge_`i' == "`c'" & trafficking_`i' == 1 & highest_charge == "`c'"
        replace drug_category = drug_category_`i'    if charge_`i' == "`c'" & trafficking_`i' == 1 & highest_charge == "`c'"
    }
}

* Drop per-slot working columns -- keep only the aggregated incident-level
* trafficking flag and drug_category (plus highest_charge) for the merge.
//drop trafficking_1 trafficking_2 trafficking_3
//drop drug_category_1 drug_category_2 drug_category_3

* Average length of probation is in Table 9 of SPAC FY-2024 Statistical Report
* https://www.nccourts.gov/assets/documents/publications/SPAC-FY-2024-Statistical-Report.pdf

drop if charge_1 == "Unknown_drug" //These are guaranteed not to be colormetric arrests. See above note.

* -----------------------------------------------------------------------------
* Collapse to one row per arrested person.
*
* After the property-onto-arrestee join, a single arrestee (identified by
* year + unique_incident_id + arrestee_sequence_number) can appear on multiple
* property rows. We reduce to one row per person, keeping the row carrying that
* person's most severe charge -- the same "highest single sentence wins" rule
* used across the three property slots above, now applied across property rows.
*
* charge_severity orders the classes from least to most severe so the max
* within each person is the controlling charge. highest_charge, trafficking,
* and drug_category are preserved from the selected (most severe) row.
* -----------------------------------------------------------------------------
gen int charge_severity = .
local s = 1
foreach c in "Misdemeanor_3" "Misdemeanor_2" "Misdemeanor_1" ///
             "Felony_I" "Felony_H" "Felony_G" "Felony_F" "Felony_E" ///
             "Felony_D" "Felony_C" "Felony_B" "Felony_A" {
    replace charge_severity = `s' if highest_charge == "`c'"
    local ++s
}

bysort year unique_incident_id arrestee_sequence_number (charge_severity): keep if _n == _N

save "$directory\data\nibrs_data_cleaned.dta", replace
