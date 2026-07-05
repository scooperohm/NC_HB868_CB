* =============================================================================
* sentence_lengths.do
*
* Builds three lookup tables that, merged onto the classified arrest data,
* yield the expected sentence length (and any mandatory fine) for each
* NC drug charge produced by classify_sentences.do.
*
* OUTPUTS:
*   empirical_sentence_lookup.dta   -- Empirical disposition mix + avg sentence
*                                      from FY 2024 NC convictions, by class x PRL
*   trafficking_sentence_lookup.dta -- G.S. 90-95(h) mandatory sentences + fines
*   probation_length_lookup.dta     -- Default probation periods (G.S. 15A-1343.2)
*
* SOURCES (all confirmed 2026-05-15):
*   [SPAC-Felony]  SPAC FY-2024 Statistical Report, Table 4: "Convictions and
*                  Sentences by Offense Class and Prior Record Level" (felonies)
*                  https://www.nccourts.gov/assets/documents/publications/SPAC-FY-2024-Statistical-Report.pdf
*   [SPAC-Misd]    SPAC FY-2024 Statistical Report, Table 19: "Convictions and
*                  Sentences by Offense Class and Prior Conviction Level" (misd.)
*                  Same report.
*   [Trafficking]  G.S. 90-95(h) -- Drug trafficking minimums + fines
*                  https://www.ncleg.net/enactedlegislation/statutes/html/bysection/chapter_90/gs_90-95.html
*                  Cross-checked vs UNC SOG Sentencing Handbook (2018) p.49.
*   [Probation]    G.S. 15A-1343.2(d) -- Default probation lengths
*                  https://www.ncleg.net/EnactedLegislation/Statutes/HTML/BySection/Chapter_15A/GS_15A-1343.2.html
*
* WHY EMPIRICAL: SPAC reports actual sentences imposed by NC judges in FY 2024,
* which captures plea deals, mitigated/aggravated departures, and credit for
* time served. Strictly better than the statutory presumptive ranges from the
* SS grid for an expected-cost model. Trafficking is exempt: G.S. 90-95(h)
* mandates fixed minimums regardless of judge discretion or prior record.
* =============================================================================



* -----------------------------------------------------------------------------
* LOOKUP 1: Empirical sentencing distribution (non-trafficking)
* -----------------------------------------------------------------------------
* For each (charge_class, prl) cell:
*   n_c, n_i, n_a, n_total    -- conviction counts (Community/Intermediate/Active)
*   p_community, p_intermediate, p_active -- disposition probabilities
*   avg_active_min_mo         -- avg MINIMUM sentence in MONTHS, conditional on
*                                Active disposition (0 if no Active in that cell)
*   avg_active_max_mo         -- avg MAXIMUM sentence in MONTHS, same conditional
*
* Misdemeanor rows: NC misdemeanor sentences are determinate (single number),
* so avg_active_min_mo = avg_active_max_mo = avg_days / 30.
*
* Felony Classes A, B1, B2 are NOT produced by classify_sentences.do (no NC
* drug crime reaches Class B2 or higher). Misdemeanor A1 likewise. Included
* here for completeness/future-proofing -- they will simply fail to merge.
* For Class A (Life/Death), avg sentences are set missing (.) since "Life"
* is not a numerical month value.
* -----------------------------------------------------------------------------

clear
* Counts and averages transcribed directly from [SPAC-Felony] Table 4 and
* [SPAC-Misd] Table 19. Column order: class, prl, n_c, n_i, n_a, n_total,
* avg_min_mo, avg_max_mo.
input str14 charge_class byte prl int n_c int n_i int n_a long n_total double avg_min_mo double avg_max_mo
    "Felony_A"     1     0     0    51    51   .     .
    "Felony_A"     2     0     0     7     7   .     .
    "Felony_A"     3     0     0     9     9   .     .
    "Felony_A"     4     0     0    13    13   .     .
    "Felony_A"     5     0     0     6     6   .     .
    "Felony_A"     6     0     0     2     2   .     .
    "Felony_B1"    1     0     0   241   241   214   291
    "Felony_B1"    2     0     0    95    95   240   318
    "Felony_B1"    3     0     0    50    50   261   342
    "Felony_B1"    4     0     0    22    22   305   389
    "Felony_B1"    5     0     0    14    14   336   426
    "Felony_B1"    6     0     0     9     9   364   455
    "Felony_B2"    1     0     0   113   113   125   174
    "Felony_B2"    2     0     0    41    41   142   193
    "Felony_B2"    3     0     0    20    20   164   213
    "Felony_B2"    4     0     0    13    13   208   269
    "Felony_B2"    5     0     0    10    10   218   283
    "Felony_B2"    6     0     0     4     4   252   326
    "Felony_C"     1     0     0   176   176    63   104
    "Felony_C"     2     0     0    95    95    68   105
    "Felony_C"     3     0     0   101   101    77   109
    "Felony_C"     4     0     0   112   112    85   117
    "Felony_C"     5     0     0    87    87   100   136
    "Felony_C"     6     0     0    82    82   112   150
    "Felony_D"     1     0    19   308   327    52    77
    "Felony_D"     2     0     0   139   139    59    84
    "Felony_D"     3     0     0   107   107    66    92
    "Felony_D"     4     0     0   102   102    75   103
    "Felony_D"     5     0     0    73    73    83   114
    "Felony_D"     6     0     0   106   106    98   131
    "Felony_E"     1   121   471   282   874    21    47
    "Felony_E"     2    39   211   169   419    25    48
    "Felony_E"     3     0     0   206   206    27    48
    "Felony_E"     4     0     0   175   175    31    51
    "Felony_E"     5     0     0   121   121    36    58
    "Felony_E"     6     0     0   153   153    42    62
    "Felony_F"     1   126   429   263   818    14    26
    "Felony_F"     2    87   261   229   577    16    29
    "Felony_F"     3    54   179   228   461    19    32
    "Felony_F"     4     0     0   234   234    21    34
    "Felony_F"     5     0     0   156   156    23    37
    "Felony_F"     6     0     0   215   215    27    42
    "Felony_G"     1    82   251    75   408    11    23
    "Felony_G"     2   239   585   247  1071    12    24
    "Felony_G"     3   171   510   303   984    14    26
    "Felony_G"     4    77   281   300   658    16    28
    "Felony_G"     5     0     0   281   281    18    31
    "Felony_G"     6     0     0   310   310    21    35
    "Felony_H"     1  1052   862   227  2141     5    16
    "Felony_H"     2   737  1228   450  2415     6    17
    "Felony_H"     3   454   801   607  1862     8    19
    "Felony_H"     4   257   522   662  1441    10    21
    "Felony_H"     5   135   331   531   997    13    24
    "Felony_H"     6     0     0  1008  1008    17    30
    "Felony_I"     1   994   279     0  1273     0     0
    "Felony_I"     2   888   814     0  1702     0     0
    "Felony_I"     3   398   815     0  1213     0     0
    "Felony_I"     4   222   377   298   897     6    17
    "Felony_I"     5   100   214   227   541     7    18
    "Felony_I"     6   131   237   379   747     9    20
end

* PRL is the felony Prior Record Level (G.S. 15A-1340.14). All counts above
* are from [SPAC-Felony] Table 4 (FY 2024). Cells with n_a=0 have no Active
* sentences imposed -> avg_min/max set to 0 (not missing) so that
* p_active * avg_min = 0 propagates cleanly in cost calculations.

* Now append misdemeanors. Misdemeanor Prior Conviction Level (PCL) only
* goes I-III, but we store it in the same `prl` column to allow a single
* merge key. [SPAC-Misd] Table 19. Sentences in days -> divided by 30.
tempfile felony_rows
save `felony_rows'

clear
input str14 charge_class byte prl int n_c int n_i int n_a long n_total double avg_days
    "Misdemeanor_A1" 1   995   218   478  1691   38
    "Misdemeanor_A1" 2  1452   358   896  2706   48
    "Misdemeanor_A1" 3  1076   383  1462  2921   86
    "Misdemeanor_1"  1  4716   117  1899  6732   20
    "Misdemeanor_1"  2  7061   396  4094 11551   27
    "Misdemeanor_1"  3  5963   672  6297 12932   53
    "Misdemeanor_2"  1  7353    20   911  8284   12
    "Misdemeanor_2"  2  3177    98  1334  4609   17
    "Misdemeanor_2"  3  1643    94  1903  3640   26
    "Misdemeanor_3"  1 16295     1  1337 17633    6
    "Misdemeanor_3"  2  5736     9  1453  7198    7
    "Misdemeanor_3"  3  5132    37  3285  8454    9
end

gen double avg_min_mo = avg_days / 30
gen double avg_max_mo = avg_days / 30
drop avg_days

append using `felony_rows'

* Compute disposition probabilities from counts..
gen double p_community    = n_c / n_total
gen double p_intermediate = n_i / n_total
gen double p_active       = n_a / n_total

* Add a sentinel Unknown_drug row for any remaining obs in classify_sentences.do
* that lack a drug type. We assume these are colormetric false positives
* that get dismissed before sentencing: zero sentence, zero disposition.
foreach p of numlist 1/6 {
    set obs `=_N+1'
    replace charge_class = "Unknown_drug" in L
    replace prl = `p' in L
    replace n_c = 0 in L
    replace n_i = 0 in L
    replace n_a = 0 in L
    replace n_total = 0 in L
    replace avg_min_mo = 0 in L
    replace avg_max_mo = 0 in L
    replace p_community = 0 in L
    replace p_intermediate = 0 in L
    replace p_active = 0 in L
}

* prl_weight = P(PRL | charge_class), drawn from the column-conditional
* distribution of FY 2024 convictions in [SPAC-Felony] Table 4 and
* [SPAC-Misd] Table 19. Used for the joinby-based row expansion in the
* merge skeleton below: each arrest becomes N rows (N = 6 for felonies,
* 3 for misdemeanors), each weighted by prl_weight, so expected cost
* per arrest = sum over PRL rows of (prl_weight * per-row cost).
bysort charge_class: egen double _class_total = total(n_total)
gen double prl_weight = n_total / _class_total
* Unknown_drug sentinel rows have n_total=0 -> uniform 1/6 weight (drops out
* anyway since avg_min_mo=0 and all dispositions are zero).
replace prl_weight = 1/6 if charge_class == "Unknown_drug"
drop _class_total

label var charge_class      "Charge class label from classify_sentences.do"
label var prl               "PRL (1-6 felony) or PCL (1-3 misdemeanor)"
label var n_c               "Count of Community sentences (FY 2024)"
label var n_i               "Count of Intermediate sentences (FY 2024)"
label var n_a               "Count of Active sentences (FY 2024)"
label var n_total           "Total convictions in this cell (FY 2024)"
label var p_community       "P(Community | conviction at this class, PRL)"
label var p_intermediate    "P(Intermediate | conviction at this class, PRL)"
label var p_active          "P(Active | conviction at this class, PRL)"
label var avg_min_mo        "Avg min sentence (months), conditional on Active"
label var avg_max_mo        "Avg max sentence (months), conditional on Active"
label var prl_weight        "P(PRL | charge_class) -- conviction-share weight"

order charge_class prl n_c n_i n_a n_total ///
      p_community p_intermediate p_active avg_min_mo avg_max_mo prl_weight

save "$directory\data\empirical_sentence_lookup.dta", replace


* -----------------------------------------------------------------------------
* LOOKUP 2: Trafficking sentences (G.S. 90-95(h))
* -----------------------------------------------------------------------------
* Trafficking overrides the empirical SS-grid distribution: sentence is
* MANDATORY by statute, independent of PRL or judge discretion. Each tier
* specifies (class, min_months, max_months, fine).
*
* All values from [Trafficking] G.S. 90-95(h), confirmed against
* UNC SOG NC Sentencing Handbook (2018) p. 49.
*
* Min/max by class (offenses on/after 12/1/2012):
*   Class C: 225-282    Class F: 70-93
*   Class D: 175-222    Class G: 35-51
*   Class E: 90-120     Class H: 25-39
*
* Weight units below are normalized to POUNDS for mass and to DOSAGE UNITS
* for unit-based drugs. (453.59237 g = 1 lb.)
* -----------------------------------------------------------------------------

clear
input str40 drug_category double weight_low double weight_high str8 weight_unit ///
      str10 charge_class int min_months int max_months long fine
    "marijuana"                10           50         "pound"   "Felony_H"    25    39    5000
    "marijuana"                50         2000         "pound"   "Felony_G"    35    51   25000
    "marijuana"              2000        10000         "pound"   "Felony_F"    70    93   50000
    "marijuana"             10000       999999         "pound"   "Felony_D"   175   222  200000
    "cocaine"             0.061729     0.440924        "pound"   "Felony_G"    35    51   50000
    "cocaine"             0.440924     0.881848        "pound"   "Felony_F"    70    93  100000
    "cocaine"             0.881848   999999            "pound"   "Felony_D"   175   222  250000
    "methamphetamine"     0.061729     0.440924        "pound"   "Felony_F"    70    93   50000
    "methamphetamine"     0.440924     0.881848        "pound"   "Felony_E"    90   120  100000
    "methamphetamine"     0.881848   999999            "pound"   "Felony_C"   225   282  250000
    "amphetamine"         0.061729     0.440924        "pound"   "Felony_H"    25    39    5000
    "amphetamine"         0.440924     0.881848        "pound"   "Felony_G"    35    51   25000
    "amphetamine"         0.881848   999999            "pound"   "Felony_E"    90   120  100000
    "opioid"              0.008818     0.030865        "pound"   "Felony_F"    70    93   50000
    "opioid"              0.030865     0.061729        "pound"   "Felony_E"    90   120  100000
    "opioid"              0.061729   999999            "pound"   "Felony_C"   225   282  500000
    "lsd"                     100          500         "du"      "Felony_G"    35    51   25000
    "lsd"                     500         1000         "du"      "Felony_F"    70    93   50000
    "lsd"                    1000       999999         "du"      "Felony_D"   175   222  200000
    "mdma_units"              100          500         "du"      "Felony_G"    35    51   25000
    "mdma_units"              500         1000         "du"      "Felony_F"    70    93   50000
    "mdma_units"             1000       999999         "du"      "Felony_D"   175   222  250000
    "mdma_mass"           0.061729     0.440924        "pound"   "Felony_G"    35    51   25000
    "mdma_mass"           0.440924     0.881848        "pound"   "Felony_F"    70    93   50000
    "mdma_mass"           0.881848   999999            "pound"   "Felony_D"   175   222  250000
    "methaqualone"           1000         5000         "du"      "Felony_G"    35    51   25000
    "methaqualone"           5000        10000         "du"      "Felony_F"    70    93   50000
    "methaqualone"          10000       999999         "du"      "Felony_D"   175   222  200000
    "synthetic_cannabinoid"    50          250         "du"      "Felony_H"    25    39    5000
    "synthetic_cannabinoid"   250         1250         "du"      "Felony_G"    35    51   25000
    "synthetic_cannabinoid"  1250         3750         "du"      "Felony_F"    70    93   50000
    "synthetic_cannabinoid"  3750       999999         "du"      "Felony_D"   175   222  200000
    "cathinone"           0.061729     0.440924        "pound"   "Felony_F"    70    93   50000
    "cathinone"           0.440924     0.881848        "pound"   "Felony_E"    90   120  100000
    "cathinone"           0.881848   999999            "pound"   "Felony_C"   225   282  250000
end

label var drug_category  "Drug category (matches normalized suspected_drug_type)"
label var weight_low     "Lower bound (inclusive) of trafficking tier"
label var weight_high    "Upper bound (exclusive) of trafficking tier"
label var weight_unit    "Unit: 'pound' (mass) or 'du' (dosage units)"
label var charge_class   "NC felony class assigned by trafficking statute"
label var min_months     "Mandatory minimum sentence (months)"
label var max_months     "Mandatory maximum sentence (months)"
label var fine           "Mandatory minimum fine (dollars)"

save "$directory\data\trafficking_sentence_lookup.dta", replace

* NOTE -- Fentanyl/carfentanyl trafficking penalties were added in S.L. 2018-44
* and again raised in S.L. 2017-115. As of writing, fentanyl/carfentanyl
* trafficking is governed by a separate subsection (90-95(h)(4c)) with HIGHER
* class assignments than ordinary opioids (e.g. 4-13g = Class E, not F).
* Current classify_sentences.do does NOT branch on fentanyl trafficking
* weights; fentanyl/carfentanyl rows currently fall into Felony_I (simple
* possession only).


* -----------------------------------------------------------------------------
* LOOKUP 3: Default probation length (G.S. 15A-1343.2(d))
* -----------------------------------------------------------------------------
* For Community or Intermediate dispositions, the court sets probation within
* these default ranges. We use the MIDPOINT of each range as expected length.
* [Probation] G.S. 15A-1343.2(d)
* -----------------------------------------------------------------------------

clear
input str8 offense_level str3 disposition int prob_min_months int prob_max_months int prob_expected_months
    "felony"   "C"     12    30    21
    "felony"   "I"     18    36    27
    "misd"     "C"      6    18    12
    "misd"     "I"     12    24    18
    "felony"   "A"      0     0     0
    "misd"     "A"      0     0     0
end

label var offense_level         "felony or misd"
label var disposition           "A=Active, I=Intermediate, C=Community"
label var prob_expected_months  "Midpoint of default probation range (G.S. 15A-1343.2(d))"

save "$directory\data\probation_length_lookup.dta", replace

display "sentence_lengths.do complete."
display "Built: empirical_sentence_lookup.dta, trafficking_sentence_lookup.dta, probation_length_lookup.dta"
