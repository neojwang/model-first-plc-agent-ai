# Agent AI for PLC programming: prompts, scoring scripts, and model-checking files

This repository accompanies the paper "Teaching Programmable Logic Controller Programming and Verification with Agent AI: A Model-First IDEF0–GRAFCET Workflow in a Virtual Factory". It contains everything needed to repeat the code-generation experiment (RQ1) and the cross-check of the verification lane (RQ2); it contains no student data.

Status: the materials are released before the experiment. The prompts are frozen with `exec/freeze_prompts.py` before the first generation, and the results (`results/`) are added after the experiment. License: MIT (see `LICENSE`).

| Path | Content |
|---|---|
| `exec/prompts/tasks/` | Task cards T1–T4 (Factory I/O Scene 2, customized Scene 3 with two timer strategies, Level Control with PID) |
| `exec/prompts/templates/` | Prompt templates: A1 lane (IDEF0, GRAFCET as JSON, ST code), A2 lane (independently phrased), single-lane baseline (ST code directly); `_schema.md` is the GRAFCET JSON schema |
| `exec/render_prompt.py` | Fills a template with a task card and the earlier response of the same lane |
| `exec/freeze_prompts.py` | SHA-256 manifest of the prompts, written before the first generation and verified before every session |
| `exec/make_run_plan.py`, `exec/run_plan.csv` | Randomized run plan: 4 tasks × 2 conditions × 30 samples (seed 20261112) |
| `exec/scene_tests_en.md` | Scene tests and pass criteria |
| `exec/compile_check.py` | Compile check (compiled, a2_compiled): repeats the first three steps of the compilation script of OpenPLC Runtime version 3 at the pinned commit (iec2c, then g++ on Config0.c and Res0.c), writes the compilation log, and writes the file to upload for the scene test |
| `exec/scene_sim.py` | Scene tests (scene_test_pass, a2_scene_test_pass) by closed-loop simulation: the compiled program, run as OpenPLC Runtime runs it, drives models of the Factory I/O scenes (nominal scene model v1, documented in `scene_tests_en.md`); no Factory I/O needed; `--sensitivity` reruns under alternative assumptions |
| `exec/set_params.py` | Sets the scene-test parameters of an upload file for one situation (timer durations of T2 and T3, PID gains of T4) and prints the log stored in test_log |
| `exec/compare_grafcet.py` | Criterion (iii): consistency of the A1 and A2 GRAFCET models (one-to-one correspondence of steps and transitions, receptivities and outputs compared over all input combinations, timers compared by owning step and preset) |
| `exec/score_models.py` | Fills the model columns of the run sheet: criterion (iii) and, for the tank tasks, the model check of the A1 GRAFCET (writes a NuSMV model per sample) |
| `nusmv/grafcet2smv.py` | GRAFCET (JSON) to NuSMV translator with an explicit-state pre-check; one model step is one evolution to a stable situation |
| `nusmv/tank_reference.*` | Reference GRAFCET of the tank tasks, its NuSMV model, and the pre-check log (properties P1–P4, well-formedness W1–W5, seeded faults) |
| `analysis/analysis.py` | Wilson intervals, pass@k, Fisher's exact test, Cochran–Mantel–Haenszel test (primary test of RQ1), false accepts and Cohen's kappa (RQ2); `--table9` writes Table 9 |
| `analysis/power_sim.py` | Monte Carlo power of the Cochran–Mantel–Haenszel test quoted in Section 3.2 |
| `results/` (added after the experiment) | Run sheet `runs.csv`; the text artifacts of every sample (IDEF0 and GRAFCET models, ST code, NuSMV models, compilation and test logs); `manifest.csv` with the SHA-256 of every artifact. Screen recordings of the scene tests are listed in the manifest but not included |

Usage:

```
python3 exec/freeze_prompts.py                          # once, before the first generation
python3 exec/render_prompt.py T2 A1_1_idef0             # prompt for one stage
python3 exec/compile_check.py --openplc OPENPLC_V3_DIR runs.csv --base ARTIFACTS --write
python3 exec/set_params.py ARTIFACTS/<run_id>/a1_code_openplc.st T2 a   # file to upload for situation (a)
python3 exec/scene_sim.py --openplc OPENPLC_V3_DIR runs.csv --base ARTIFACTS --write --sensitivity
python3 exec/score_models.py runs.csv --base ARTIFACTS --write
NuSMV ARTIFACTS/<run_id>/a1_grafcet.smv
python3 analysis/analysis.py runs.csv --table9 table9.csv > report.md
```

Python 3 is required; numpy and scipy are used by `power_sim.py` and, when installed, by `analysis.py`; NuSMV 2.6 is required for the formal model check; the compile check and the scene simulation need OpenPLC_v3 at commit b5d41356dab4aeadca0dd7ca64ba542f870b595d with matiec built (flex, bison, libtool and g++); Factory I/O is needed only to repeat the scene tests in the simulator itself. Self-tests: `python3 exec/compare_grafcet.py --selftest`, `python3 exec/set_params.py --selftest`, `python3 exec/scene_sim.py --openplc OPENPLC_V3_DIR --selftest`, `python3 analysis/analysis.py --selftest`, `python3 nusmv/grafcet2smv.py nusmv/tank_reference.json --check --mutants`.
