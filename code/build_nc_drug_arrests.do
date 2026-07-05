* =============================================================================
* build_nc_drug_arrests.do
*
* Build a 2019-2024 dataset of North Carolina drug/narcotic-violation arrests
* (arrestee segment) with their associated property segments left-merged on.
* -----------------------------------------------------------------------------
* Source: Jacob Kaplan's concatenated NIBRS files (parquet), one per year.
* =============================================================================

tempfile arrestee_nc property_nc

* -----------------------------------------------------------------------------
* 1. ARRESTEE segment: North Carolina, drug/narcotic violations, 2019-2024
* -----------------------------------------------------------------------------
forval year = 2019/2024 {
    pq use "$directory\data\nibrs_arrestee_segment_`year'.parquet", clear
    keep if state == "north carolina"
    keep if ucr_arrest_offense_code == "drug/narcotic offenses - drug/narcotic violations"
    if `year' > 2019 append using `arrestee_nc'
    save `arrestee_nc', replace
}

* -----------------------------------------------------------------------------
* 2. PROPERTY segment: North Carolina, 2019-2024
* -----------------------------------------------------------------------------
forval year = 2019/2024 {
    pq use "$directory\data\nibrs_property_segment_`year'.parquet", clear
    keep if state == "north carolina"
    if `year' > 2019 append using `property_nc'
    save `property_nc', replace
}

* -----------------------------------------------------------------------------
* 3. Left-merge property onto arrestee at the incident level.
*    An incident can hold multiple arrestees and multiple property records,
*    so this is a many-to-many join on unique_incident_id. joinby forms the
*    cartesian product within each incident; unmatched(master) keeps drug
*    arrestees that have no associated property record. In later steps, 
*	 arrestees without an associated property record are dropped, and arrestees 
*	 with multiple property records are collapsed into one row, keeping the 
*	 single highest offense associated with the drugs in the property segment.
* -----------------------------------------------------------------------------
use `arrestee_nc', clear
joinby unique_incident_id using `property_nc', unmatched(master) _merge(_merge_property)

* -----------------------------------------------------------------------------
* 4. Keep only rows involving seized drug property.
*    Drops arrestee rows whose attached property is not seized drugs, as well
*    as the unmatched(master) arrestees that had no property record at all.
* -----------------------------------------------------------------------------
keep if type_of_property_loss == "seized" & property_description == "drugs/narcotics"

* -----------------------------------------------------------------------------
* 5. Save
* -----------------------------------------------------------------------------
save "$directory\data\nc_drug_arrests_2019_2024", replace

