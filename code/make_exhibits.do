* =============================================================================
* make_exhibits.do
*
* Builds the publication exhibits consumed by the LaTeX writeup, exported
* into the LaTeX project's figures\ subfolder so the document autocompiles:
*
*   1. cost_by_type_scenario.tex   tabular: mean E[cost]/arrest by drug type x
*                                  model specification (the 5 scenarios)
*   2. arrests_by_type_year.tex    tabular: NIBRS drug arrests by type x year
*   3. results_macros.tex          headline scalars as \newcommand macros so the
*                                  prose numbers stay in sync with the data
*   4. costbenefit_timeseries.png  two side-by-side panels (baseline vs all-
*                                  midpoint) of cumulative policy cost vs
*                                  cumulative avoided waste, 2019 onward
*   5. scenario_summary.tex        tabular: cost per arrest, annual colorimetric
*                                  waste, and expected annual policy savings,
*                                  one row per assumption scenario
*
* Inputs (built upstream by cost_scenarios.do):
*   $directory\data\waste_by_scenario.dta        (scenario x drug_bucket)
*   $directory\data\waste_by_scenario_year.dta   (scenario x year)
*   $directory\data\arrests_cost_by_type_year.dta (year x drug_bucket, baseline)
* =============================================================================

* inherited in-pipeline. Fallbacks fire only on a standalone run.
if "$latexdir" == ""        global latexdir  "$directory\LaTeX"

* All generated exhibits land in the LaTeX project's figures\ subfolder; the
* two hand-written documents (methodology, executive summary) \input from here.
global figdir "$latexdir\figures"
if "$c_policy_annual" == "" global c_policy_annual 797772
if "$colormetric_error_rate"     == "" global colormetric_error_rate     .037
if "$proportion_colormetric_use" == "" global proportion_colormetric_use .499


* -----------------------------------------------------------------------------
* EXHIBIT 1: mean cost per arrest by drug type x model specification
* -----------------------------------------------------------------------------
use "$directory\data\waste_by_scenario.dta", clear
keep scenario drug_bucket mean_cost
reshape wide mean_cost, i(drug_bucket) j(scenario) string

* Row order + display labels for the four buckets plus the all-types row.
gen byte _ord = .
gen str25 _lab = ""
replace _ord = 1 if drug_bucket == "marijuana"
replace _lab = "Marijuana"           if drug_bucket == "marijuana"
replace _ord = 2 if drug_bucket == "cocaine_opioids"
replace _lab = "Opium/cocaine"       if drug_bucket == "cocaine_opioids"
replace _ord = 3 if drug_bucket == "synthetic_narcotics"
replace _lab = "Synthetic narcotics" if drug_bucket == "synthetic_narcotics"
replace _ord = 4 if drug_bucket == "other_nonnarcotic"
replace _lab = "Other non-narcotics" if drug_bucket == "other_nonnarcotic"
replace _ord = 5 if drug_bucket == "ALL"
replace _lab = "All drug types"      if drug_bucket == "ALL"
sort _ord

file open tbl using "$figdir\cost_by_type_scenario.tex", write replace
file write tbl "\begin{tabular}{l r r r r r}" _n
file write tbl "\hline" _n
file write tbl "Drug type & Baseline & High prob. & High cost & High sent. & All midpt. \\" _n
file write tbl "\hline" _n
forval i = 1/`=_N' {
    local lab = _lab[`i']
    foreach s in baseline prob_high cost_high sentence_high all_avg {
        local v = mean_cost`s'[`i']
        local c_`s' = trim("`: di %9.0fc `v''")
    }
    file write tbl "`lab' & `c_baseline' & `c_prob_high' & `c_cost_high' & `c_sentence_high' & `c_all_avg' \\" _n
}
file write tbl "\hline" _n
file write tbl "\end{tabular}" _n
file close tbl


* -----------------------------------------------------------------------------
* EXHIBIT 2: NIBRS drug arrests by type x year
* -----------------------------------------------------------------------------
use "$directory\data\arrests_cost_by_type_year.dta", clear
keep year drug_bucket n_arrests
reshape wide n_arrests, i(year) j(drug_bucket) string
foreach v of varlist n_arrests* {
    replace `v' = 0 if missing(`v')   //a bucket absent in a given year -> 0
}
egen long _tot = rowtotal(n_arrests*)
sort year

file open atbl using "$figdir\arrests_by_type_year.tex", write replace
file write atbl "\begin{tabular}{l r r r r r}" _n
file write atbl "\hline" _n
file write atbl "Year & Marijuana & Opium/cocaine & Synthetic narc. & Other non-narc. & Total \\" _n
file write atbl "\hline" _n
forval i = 1/`=_N' {
    local yr = year[`i']
    local mar = trim("`: di %9.0fc n_arrestsmarijuana[`i']'")
    local coc = trim("`: di %9.0fc n_arrestscocaine_opioids[`i']'")
    local syn = trim("`: di %9.0fc n_arrestssynthetic_narcotics[`i']'")
    local oth = trim("`: di %9.0fc n_arrestsother_nonnarcotic[`i']'")
    local tot = trim("`: di %9.0fc _tot[`i']'")
    file write atbl "`yr' & `mar' & `coc' & `syn' & `oth' & `tot' \\" _n
}
file write atbl "\hline" _n
file write atbl "\end{tabular}" _n
file close atbl


* -----------------------------------------------------------------------------
* EXHIBIT 3: headline-number macros for the prose
* -----------------------------------------------------------------------------
* Number of years covered by the data (annualization denominator).
use "$directory\data\waste_by_scenario_year.dta", clear
quietly levelsof year, local(yrs)
local nyears : word count `yrs'
local minyr  : word 1 of `yrs'
local maxyr  : word `nyears' of `yrs'

use "$directory\data\waste_by_scenario.dta", clear

* Pull annual waste (= avoided cost = benefit) and arrest counts for the two
* headline specifications, all drug types.
quietly summ annual_waste if scenario == "baseline" & drug_bucket == "ALL"
local ben_base = r(mean)
quietly summ annual_waste if scenario == "all_avg" & drug_bucket == "ALL"
local ben_mid = r(mean)
quietly summ n_arrests if scenario == "baseline" & drug_bucket == "ALL"
local arr_tot = r(mean)
local arr_ann = `arr_tot' / `nyears'

local policy = $c_policy_annual
local net_base = `ben_base' - `policy'
local net_mid  = `ben_mid'  - `policy'
local bcr_base = `ben_base' / `policy'
local bcr_mid  = `ben_mid'  / `policy'

* Baseline mean cost per arrest, by bucket (matches the cost-benefit summary).
foreach b in marijuana cocaine_opioids synthetic_narcotics other_nonnarcotic {
    quietly summ mean_cost if scenario == "baseline" & drug_bucket == "`b'"
    local cost_`b' = r(mean)
}

* Expected waste per colorimetric test on a marijuana arrest (= baseline cost x
* false-positive rate) and the share of arrests that use a colorimetric test.
local cost_mar_fp = `cost_marijuana' * $colormetric_error_rate
local pct_tests   = $proportion_colormetric_use * 100

* Pre-format every value into a local (comma grouping; ratios to 1 decimal),
* then write plain strings -- avoids fragile nested macro expansion in file write.
local arr_tot_f = trim("`: di %12.0fc `arr_tot''")
local arr_ann_f = trim("`: di %12.0fc `arr_ann''")
local policy_f  = trim("`: di %12.0fc `policy''")
local benB_f    = trim("`: di %12.0fc `ben_base''")
local benM_f    = trim("`: di %12.0fc `ben_mid''")
local netB_f    = trim("`: di %12.0fc `net_base''")
local netM_f    = trim("`: di %12.0fc `net_mid''")
local bcrB_f    = trim("`: di %4.1f `bcr_base''")
local bcrM_f    = trim("`: di %4.1f `bcr_mid''")
local cMar_f    = trim("`: di %9.0fc `cost_marijuana''")
local cCoc_f    = trim("`: di %9.0fc `cost_cocaine_opioids''")
local cSyn_f    = trim("`: di %9.0fc `cost_synthetic_narcotics''")
local cOth_f    = trim("`: di %9.0fc `cost_other_nonnarcotic''")
local cMarFP_f  = trim("`: di %9.0fc `cost_mar_fp''")
local pctT_f    = trim("`: di %4.1f `pct_tests''")

file open mac using "$figdir\results_macros.tex", write replace
file write mac "% Auto-generated by make_exhibits.do -- do not edit by hand." _n
file write mac "\newcommand{\resNyears}{`nyears'}" _n
file write mac "\newcommand{\resMinYear}{`minyr'}" _n
file write mac "\newcommand{\resMaxYear}{`maxyr'}" _n
file write mac "\newcommand{\resArrestsTotal}{`arr_tot_f'}" _n
file write mac "\newcommand{\resArrestsAnnual}{`arr_ann_f'}" _n
file write mac "\newcommand{\resPolicyCost}{`policy_f'}" _n
file write mac "\newcommand{\resBenefitBase}{`benB_f'}" _n
file write mac "\newcommand{\resBenefitMid}{`benM_f'}" _n
file write mac "\newcommand{\resNetBase}{`netB_f'}" _n
file write mac "\newcommand{\resNetMid}{`netM_f'}" _n
file write mac "\newcommand{\resBcrBase}{`bcrB_f'}" _n
file write mac "\newcommand{\resBcrMid}{`bcrM_f'}" _n
file write mac "\newcommand{\resCostMar}{`cMar_f'}" _n
file write mac "\newcommand{\resCostCoc}{`cCoc_f'}" _n
file write mac "\newcommand{\resCostSyn}{`cSyn_f'}" _n
file write mac "\newcommand{\resCostOth}{`cOth_f'}" _n
file write mac "\newcommand{\resCostMarFP}{`cMarFP_f'}" _n
file write mac "\newcommand{\resPctTests}{`pctT_f'}" _n
file close mac


* -----------------------------------------------------------------------------
* EXHIBIT 4: cumulative cost vs benefit time series (two panels)
* -----------------------------------------------------------------------------
capture set scheme s2color

* Render graph text in the LaTeX document's serif
graph set window fontface "LM Roman 10"

foreach dev in ps eps pdf svg {
    capture graph set `dev' fontface "LM Roman 10"
}

* Okabe-Ito colourblind-safe palette (RGB): benefit = blue, cost = vermillion.
local cben  "0 114 178"
local ccost "213 94 0"

use "$directory\data\waste_by_scenario_year.dta", clear
quietly levelsof year, local(yrs)
local minyr : word 1 of `yrs'
local nyy   : word count `yrs'
local maxyr : word `nyy' of `yrs'

foreach s in baseline all_avg {
    preserve
        keep if scenario == "`s'"
        sort year
        gen double cum_benefit = sum(total_waste)
        * Step cost: the full analyzer fleet is bought up front (= 4 x the
        * annualized figure, since the annual cost is the purchase amortized
        * over the 4-year service life) and re-bought every 4 years. Cumulative
        * cost is flat within each 4-year block and steps up at each repurchase.
        gen double cum_cost = (floor((_n - 1) / 4) + 1) * $c_policy_annual * 4

        if "`s'" == "baseline" local ttl "Most conservative assumptions"
        else                   local ttl "Midpoint assumptions"

        * Plot in $millions for readable axis labels.
        gen double cum_benefit_m = cum_benefit / 1e6
        gen double cum_cost_m    = cum_cost    / 1e6

        twoway ///
            (rarea cum_cost_m cum_benefit_m year, ///
                 fcolor("`cben'") fintensity(8) lcolor(none)) ///
            (line cum_cost_m year, ///
                 lwidth(medthick) lcolor("`ccost'") lpattern(dash) connect(J)) ///
            (connected cum_benefit_m year, ///
                 lwidth(thick) lcolor("`cben'") ///
                 msymbol(O) msize(small) mcolor("`cben'") mlcolor(white) mlwidth(vthin)), ///
            title("`ttl'", size(vlarge) color(gs3)) ///
            ytitle("Cumulative dollars (millions)", size(large) color(gs6)) ///
            xtitle("") ///
            xlabel(`minyr'(1)`maxyr', labsize(large) labcolor(gs6) tlcolor(gs11)) ///
            ylabel(#6, angle(0) format(%4.1f) labsize(large) labcolor(gs6) ///
                   grid glcolor(gs15) glwidth(vthin) tlcolor(none)) ///
            yscale(lcolor(gs11)) xscale(lcolor(gs11)) ///
            legend(order(3 "Waste avoided" ///
                         2 "Policy cost") ///
                   rows(1) size(medlarge) symxsize(7) region(lcolor(none)) position(6)) ///
            plotregion(lcolor(none) margin(l=1 r=3 b=1 t=2)) ///
            graphregion(color(white) margin(medium)) ///
            name(g_`s', replace) nodraw
    restore
}

graph combine g_baseline g_all_avg, rows(1) imargin(medium) xsize(9) ysize(4) ///
    graphregion(color(white) margin(small)) plotregion(color(white)) ///
    title("Cumulative cost vs. benefit of statewide confirmatory testing", ///
          size(large) color(gs2))
graph export "$figdir\costbenefit_timeseries.png", replace width(3000)


* -----------------------------------------------------------------------------
* EXHIBIT 5: scenario summary -- cost per arrest, colorimetric waste, savings
* -----------------------------------------------------------------------------
* One row per assumption scenario, all drug types pooled. Everything is put on
* an ANNUAL basis, because the policy cost ($c_policy_annual) is defined
* annually: annual waste is the avoided-cost benefit, and savings is that
* benefit net of the policy's own annual cost.

use "$directory\data\waste_by_scenario.dta", clear
keep if drug_bucket == "ALL"
keep scenario mean_cost annual_waste

gen double policy_savings = annual_waste - $c_policy_annual

label variable mean_cost "Expected Cost per Arrest"
label variable annual_waste "Annual Waste"
label variable policy_savings "Annual TruNarc Savings"

* Row order + display labels, matching the column order of Exhibit 1.
gen byte _ord = .
gen str30 _lab = ""
replace _ord = 1 if scenario == "baseline"
replace _lab = "Most conservative"      if scenario == "baseline"
replace _ord = 2 if scenario == "prob_high"
replace _lab = "High probabilities"     if scenario == "prob_high"
replace _ord = 3 if scenario == "cost_high"
replace _lab = "High stage costs"       if scenario == "cost_high"
replace _ord = 4 if scenario == "sentence_high"
replace _lab = "High sentence lengths"  if scenario == "sentence_high"
replace _ord = 5 if scenario == "all_avg"
replace _lab = "All midpoint"           if scenario == "all_avg"
sort _ord

file open stbl using "$figdir\scenario_summary.tex", write replace
file write stbl "\begin{tabular}{@{}l r r r@{}}" _n
file write stbl "\hline" _n
file write stbl "Scenario & Cost per arrest & Annual waste & Annual TruNarc savings \\" _n
file write stbl "\hline" _n
forval i = 1/`=_N' {
    local lab = _lab[`i']
    local cpa = trim("`: di %12.0fc mean_cost[`i']'")
    local wst = trim("`: di %12.0fc annual_waste[`i']'")
    local sav = trim("`: di %12.0fc policy_savings[`i']'")
    * No $ signs in the cells: Stata reads \$ in a string as a literal $, which
    * would open math mode in LaTeX. The units live in the caption instead.
    file write stbl "`lab' & `cpa' & `wst' & `sav' \\" _n
}
file write stbl "\hline" _n
file write stbl "\end{tabular}" _n
file close stbl

di as text ""
di as text "===== (E5) Scenario summary (all drug types, annual basis) ====="
list _lab mean_cost annual_waste policy_savings, noobs abbreviate(20)


di as text ""
di as text "make_exhibits.do complete. Wrote into $figdir :"
di as text "  cost_by_type_scenario.tex, arrests_by_type_year.tex,"
di as text "  results_macros.tex, costbenefit_timeseries.png,"
di as text "  scenario_summary.tex"
