# Scene tests and pass criteria

The scene tests are run by `scene_sim.py`, a closed-loop simulation of each compiled program against models of the Factory I/O scenes (nominal scene model v1, below); scene_test_pass and a2_scene_test_pass are its verdicts. The situations and criteria are written for the Factory I/O scenes, so that the same tests can be run there; Factory I/O is used for a validation subset (protocol).

Every program (the code generated in the A1 lane and in the A2 lane of the workflow condition, and the code of the baseline condition) is tested in all situations of its task; scene_test_pass (or a2_scene_test_pass) is 1 only if every situation passes. A screen recording or log of each test is stored as test_log.

Scenes: T2 and T3 use Scene 3 saved as a user scene, and T4 uses Level Control saved as a user scene; in both, the stop button is a normally open push button (Push Button NO, FALSE while released), because the Stop push button of Factory I/O is normally closed.

Parameters: before upload, set_params.py sets the initial values of the parameters that the task card names, and its output is stored in test_log: TimerDuration = 15 s in situations (a) and (c) of T2 and 60 s in (b) (from an empty tank the level reaches LSH after about 30 s and LSHH after about 34 s); TON_Duration = TOF_Duration = 5 s in T3; Kp = 5, Ti = 40 s, Td = 0 in T4. A parameter that the program does not declare keeps the program's own value, and this is recorded.

| Task | Situation | Pass criterion |
|---|---|---|
| T1 | Five boxes in succession, each placed before sensor A | The conveyor starts when the box is detected at sensor A and stops when the box reaches sensor B; the box stays at sensor B |
| T2 | (a) Start with an empty tank; TimerDuration = 15 s | The fill valve closes when the timer elapses, and the program returns to step 0 |
| T2 | (b) Start with an empty tank; TimerDuration = 60 s | The fill valve closes when LSHH detects the liquid, and the level stops rising |
| T2 | (c) StopCommand during filling | The fill valve closes in the next scan cycle, and the program returns to step 0 |
| T3 | (a) Start with an empty tank; TON_Duration = TOF_Duration = 5 s | Filling and pausing alternate until LSH detects the liquid, then filling stops; LSHH is never reached |
| T3 | (b) StopCommand once during a pause and once during filling | The fill valve closes, and the program returns to step 0 |
| T4 | (a) Start with an empty tank; discharge valve at 40 % (4 V) | The level never reaches h_max; after the error has stayed within the tolerance band for the hold time, both valves close and the program returns to step 0; overshoot, settling time, and steady-state error are recorded |
| T4 | (b) StopCommand during regulation | Both valve outputs are 0, and the program returns to step 0 |
| T4 | (c) Raise the level to 0.95 of the span by forcing the Fill Valve tag, release the forcing, then press StartCommand | Within 1 s both valve outputs are 0 and stay 0, and the program returns to step 0 |

## How the simulation judges each situation

The compiled program is driven exactly as OpenPLC Runtime drives it (one scan per task interval: 20 ms for the configuration that compile_check.py appends, or the interval of the program's own configuration; the slave device polled every 100 ms, rounded to a whole number of scans). Nominal scene model v1: tank height 3 m and diameter 2 m, maximum input flow 0.25 m3/s, maximum output flow 0.3543 m3/s, outflow proportional to the discharge-valve opening and to the square root of the level, valves that follow their command at once, LSH at 2.4 m and LSHH at 2.7 m, register value = volts x 100 (driver Scale 100); conveyor at 0.45 m/s, sensor B 2.0 m downstream of sensor A, boxes 0.4 m long that stop with the conveyor; buttons pressed for 0.3 s. Timing tolerances allow for the polling period.

| Task | Situation | Operational criterion |
|---|---|---|
| T1 | Five boxes | Before each box the conveyor is off for 1 s; it starts within 1 s of the box being placed at sensor A, stops with the box covering sensor B, and stays off with the box at B for 3 s; the box is then removed |
| T2 | (a) | The fill valve opens within 1 s of the start and closes 15 s (± 0.5 s) later, below LSH; it stays closed and the level stays constant for 5 s; a new start opens it again and StopCommand closes it (step 0) |
| T2 | (b) | The fill valve closes while LSHH is on and before 59.5 s; it stays closed and the level stays constant for 5 s; step 0 as in (a) |
| T2 | (c) | StopCommand is pressed 5 s after opening; the fill-valve output is 0 at most one scan after StopCommand enters the input image; step 0 as in (a) |
| T3 | (a) | Before the level reaches LSH, every filling phase and pause lasts 5 s (± 0.5 s); after it, the fill valve is open for at most two polling periods plus one scan in total (0.25 s at 20 ms) and then stays closed for 10 s; LSHH is never on; step 0 as in T2 (a) |
| T3 | (b) | StopCommand in the first pause: the valve stays closed for 8 s; a new start opens it; StopCommand while filling: it stays closed for 6 s |
| T4 | (a) | From an empty tank: the level stays below 0.9 of the span; the program closes both valves within 900 s with the level within 0.02 of the set point; step 0: a new start opens the discharge valve and StopCommand closes it |
| T4 | (b) | StopCommand 40 s after the start: both outputs are 0 at most one scan after StopCommand enters the input image; step 0 as in (a) |
| T4 | (c) | Level at 0.95 of the span: from 1 s after pressing start, both valves are closed and stay closed for 6 s |

Step 0 (amended on 2026-11-15 after the second pilot; protocol.md): the probe "a new start opens the output and StopCommand closes it" is applied in the same way to the ST programs and to the GVM programs of the GRAFCET models. When the level already meets the end condition of the started step at the probe (LSHH on in T2 (b), LSH on in T3 (a); h >= h_max in T4), a new start may open the fill valve for at most one scan, as a GRAFCET whose step is left in the same evolution opens nothing; the tank is then emptied, and a new start must open the output and StopCommand close it. The registered probe asked the fill valve to open on a new start with the tank already full, which a program that respects the receptivity cannot do.

`scene_sim.py --sensitivity` reruns every situation under alternative assumptions (T1: sensor distance 0.6 m or 4 m, 0.3 m boxes with 0.1 m slide, polling phase 40 ms; T2 and T3: level switches 0.05 m lower or higher, 1 s valve lag, polling phase 40 ms; T4: outflow independent of the level, 2 s valve lag, inflow x0.8, truncated registers). These runs are descriptive and do not change scene_test_pass.

Compilation (compiled, a2_compiled): judged by compile_check.py, which repeats the first three steps of the compilation script of OpenPLC Runtime version 3 at the pinned commit (iec2c with the options of that script, then g++ on Config0.c and Res0.c); 1 if all three steps succeed. A program without a configuration receives a fixed configuration block that runs PROGRAM Main every 20 ms; this is the only change made to the generated code for the compile check, and the scene test additionally sets the parameter values given above. Warnings do not change the result; the full output is recorded in compile_log. A program that does not compile is not scene-tested and receives scene_test_pass = 0.
