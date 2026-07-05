* =============================================================================
* params.do
*
* Central parameter file for the cost model. Defines every cost, probability,
* and colorimetric-testing global used downstream by estimate_costs.do,
* cost_scenarios.do, and make_exhibits.do. Editing a value here and re-running
* the pipeline propagates it through the entire analysis.
*
* Sources: colorimetric use/error rates from the Quattrone Center report;
* process probabilities and stage costs from the 2023 Baltimore (JHU) simple-
* drug-possession cost study (lower-bound estimates used here as the baseline).
* =============================================================================


* -----------------------------------------------------------------------------
* Colorimetric use and error
* -----------------------------------------------------------------------------
global colormetric_error_rate .037 //Average colormetric false positive report from the Quattrone Report
global proportion_colormetric_use .499 //The proportion of arrests that are based on colormetric tests (maybe someone is obviously smoking weed and you don't need to test them). This specific number comes from the Quattrone report

* -----------------------------------------------------------------------------
* Testing Costs
* -----------------------------------------------------------------------------
global c_colormetric 2 //Cost of a colormetric test
global colormetric_tests_per_arrest 1.2
global c_handheld_tester 10000 //Cost of a TrueNarc or equivalent drug tester
global c_GC_machine 100000 //Cost of a GC machine

* -----------------------------------------------------------------------------
* Probabilities related to the arrest and plea process
* -----------------------------------------------------------------------------
* Lower-bound estimates from https://americanhealth.jhu.edu/sites/default/files/estimating-economic-costs-prosecuting-simple-drug-possession-baltimore-city-april-2023.pdf
global p_booking .95 //Probability that arrest leads to booking
global p_arraignment 1 //Probability that booking leads to arraignment
global p_pre_trial .95 //Probability that arraignment leads to pretrial
global p_bail_review 1 //Probability that pre-trial leads to bail review
global p_dismissed_after_bail_review .05 //Probability that charges are dismissed after bail review
* 3 Bond Options
	global p_released .9 //Probability released after bail review
	global p_home_confinement .05 //Probability home confinement after bail review
	global p_held_in_custody .05 //Probability held in custody until hearing after bail review
global p_case_preperation 1 //Probability case goes from bond to review
global p_charges_dismissed .66 //Probability charges dismissed after case preperation
global p_case_presentation .34 //Probability case moves from preperation to presentation (this includes the plea process)
* 3 Case Outcomes (that incur costs)
global p_sent_outcome_wo_cost .62 //Probability the outcome of pleadings/trial has no cost to the justice system (i.e. not-guilty verdict, drug treatment program, etc.)
	
* -----------------------------------------------------------------------------
* Costs related to the arrest and plea process (dollars)
* -----------------------------------------------------------------------------
global c_arrest 54
global c_booking 226
global c_pre_trial 76
global c_held_in_custody 1847
global c_case_preparation 1117
global c_case_outcome 170
global c_probation_visit 13 //cost per probation visit--assumed to be monthly
global c_prison 48156 //cost of imprisoning an inmate (yearly)

* -----------------------------------------------------------------------------
* Proposed-policy cost
* -----------------------------------------------------------------------------
* Every NC booking facility buys a TruNarc handheld
* analyzer (assumed 4-yr life), annualized. From the cost-benefit summary:
* $(28,815 * 1.27)/4 * 109 detention centers = $997,215/yr (2026 dollars).
global c_policy_annual 997215 //Annual statewide cost of the TruNarc confirmatory-testing policy

