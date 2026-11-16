# Analysis report

## RQ1, primary since 2026-11-14: GRAFCET models run as GVM programs (gvm/gvm_scene.py)

| Task | Lane | n | Python passed | R_gvm [95% CI] | C++ passed | NA | E3 > 0 |
|---|---|---|---|---|---|---|---|
| T1 | A1 | 30 | 30 | 1.00 [0.89, 1.00] | 30 | 0 | 0 |
| T1 | A2 | 30 | 30 | 1.00 [0.89, 1.00] | 30 | 0 | 0 |
| T2 | A1 | 30 | 30 | 1.00 [0.89, 1.00] | 30 | 0 | 0 |
| T2 | A2 | 30 | 30 | 1.00 [0.89, 1.00] | 30 | 0 | 0 |
| T3 | A1 | 30 | 30 | 1.00 [0.89, 1.00] | 30 | 0 | 0 |
| T3 | A2 | 30 | 30 | 1.00 [0.89, 1.00] | 30 | 0 | 0 |
| T4 | A1 | 30 | 30 | 1.00 [0.89, 1.00] | 30 | 0 | 0 |
| T4 | A2 | 30 | 30 | 1.00 [0.89, 1.00] | 30 | 0 | 0 |

A1 GRAFCET (GVM, Python) against the A1 ST program of the same sample (scene_test_pass):

| | ST program passed | ST program failed |
|---|---|---|
| GRAFCET passed | 116 | 4 |
| GRAFCET failed or NA | 0 | 0 |

## ST programs against the GVM programs of their GRAFCET (descriptive; gvm/st_match.py)

| Task | Lane | n | match | no match | NA | lasting differences |
|---|---|---|---|---|---|---|
| T1 | A1 | 30 | 30 | 0 | 0 | 0 |
| T1 | A2 | 30 | 30 | 0 | 0 | 0 |
| T2 | A1 | 30 | 30 | 0 | 0 | 0 |
| T2 | A2 | 30 | 30 | 0 | 0 | 0 |
| T3 | A1 | 30 | 15 | 15 | 0 | 165 |
| T3 | A2 | 30 | 30 | 0 | 0 | 0 |
| T4 | A1 | 30 | 29 | 0 | 1 | 0 |
| T4 | A2 | 30 | 30 | 0 | 0 | 0 |

## RQ1, secondary since 2026-11-14: ST programs compiled with matiec and run in the scene tests (OpenPLC)

| Task | Condition | n | Compiled | R_syn [95% CI] | Passed | R_fun [95% CI] | pass@1 | pass@5 |
|---|---|---|---|---|---|---|---|---|
| T1 | workflow | 30 | 30 | 1.00 [0.89, 1.00] | 30 | 1.00 [0.89, 1.00] | 1.00 | 1.00 |
| T1 | baseline | 30 | 30 | 1.00 [0.89, 1.00] | 30 | 1.00 [0.89, 1.00] | 1.00 | 1.00 |
| T1 | Fisher exact (workflow vs baseline, R_fun) | | | | | p = 1.0000 | | |
| T2 | workflow | 30 | 30 | 1.00 [0.89, 1.00] | 30 | 1.00 [0.89, 1.00] | 1.00 | 1.00 |
| T2 | baseline | 30 | 30 | 1.00 [0.89, 1.00] | 30 | 1.00 [0.89, 1.00] | 1.00 | 1.00 |
| T2 | Fisher exact (workflow vs baseline, R_fun) | | | | | p = 1.0000 | | |
| T3 | workflow | 30 | 30 | 1.00 [0.89, 1.00] | 30 | 1.00 [0.89, 1.00] | 1.00 | 1.00 |
| T3 | baseline | 30 | 30 | 1.00 [0.89, 1.00] | 30 | 1.00 [0.89, 1.00] | 1.00 | 1.00 |
| T3 | Fisher exact (workflow vs baseline, R_fun) | | | | | p = 1.0000 | | |
| T4 | workflow | 30 | 29 | 0.97 [0.83, 0.99] | 26 | 0.87 [0.70, 0.95] | 0.87 | 1.00 |
| T4 | baseline | 30 | 26 | 0.87 [0.70, 0.95] | 25 | 0.83 [0.66, 0.93] | 0.83 | 1.00 |
| T4 | Fisher exact (workflow vs baseline, R_fun) | | | | | p = 1.0000 | | |

Secondary test of RQ1 (primary until 2026-11-14) - Cochran-Mantel-Haenszel test over tasks (R_fun, continuity-corrected): chi2 = 0.000, p = 1.0000, MH common odds ratio = 1.30. The per-task Fisher tests above are descriptive.

## RQ2: A2 model-conformance verdict vs NuSMV verdict on the A1 GRAFCET (tank tasks)

| | NuSMV: all hold | NuSMV: violation |
|---|---|---|
| A2 accepts | 54 | 0 |
| A2 rejects | 36 | 0 |

Primary measure - A2 false accepts (A2 accepts, NuSMV finds a violation): 0 of 54 accepted samples = 0.00 [Wilson 95% CI 0.00, 0.07]

Secondary: agreement = 0.60; Cohen kappa = 0.00 [-0.25, 0.25] (kappa is depressed when one verdict dominates)

Discrepancy classes reported by A2: receptivity (no correspondence with equivalent receptivities) = 34, transition count (7 vs 5) = 2

Results table (Section 5.5) written to results_table.csv

