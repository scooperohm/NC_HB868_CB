frames reset

* Set this
global directory "C:\Users\scoop\OneDrive\Desktop\nc_colorimetric_final"
global latexdir "$directory\LaTeX"

do "$directory\code\params.do" //parameters for cost estimation

do "$directory\code\build_nc_drug_arrests.do" //Build NC 2019-2024 drug arrests (arrestee segment) with associated seized-drug property segments left-merged on
use "$directory\data\nc_drug_arrests_2019_2024", clear

do "$directory\code\classify_sentences.do" //convert weights, classify sentences by drug type and amount, choose the highest single offense type for each arrest

do "$directory\code\sentence_lengths.do" //assign sentence lengths based on probability distributions of sentencing type|offense class, priors|offense class, and sentence length/type|offense class & priors

do "$directory\code\estimate_costs.do" //estimate total costs and deadweight loss from colormetrics using the probabilities and costs supplied in main.do

do "$directory\code\cost_scenarios.do" //arrests & cost per arrest by drug type/year, plus annual colorimetric waste under each assumption scenario (sums waste_per_arrest)

do "$directory\code\make_exhibits.do" //export LaTeX tables and charts into $latexdir\figures
