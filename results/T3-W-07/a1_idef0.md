## 1. Model scope and conventions

**A0 — Control timed tank filling**

The model controls filling in three steps: **step 0**, **filling step**, and **pause step**. The discharge valve remains closed throughout.

In the IDEF0 model:

- **Inputs** are signals or information transformed by a function.
- **Controls** are rules, parameters, and constraints governing that transformation.
- **Outputs** are the resulting signals or information.
- **Mechanisms** are the resources performing the function.
- Every function has a verb-phrase name; every arrow has a noun-phrase name. Backticked identifiers retain the required vocabulary.

**Safety interpretation:** LSH terminates normal filling at 2.4 m. This model additionally treats LSHH as a protective shutdown condition. That is a conservative design decision, not a substitute for preventing the level from reaching 2.7 m. The “LSHH must never be reached” requirement also requires adequate physical margin for scan delay, communications delay, valve closure, and residual inflow.

## 2. A0 context and child-function ICOM table

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control timed tank filling** | Start-button signal; stop-button signal; high-level indication; high-high-level indication | Initial-step rule; start-event rule; stop-priority rule; timed filling and pause rules; level-termination rule; high-high protection rule; closed-discharge rule; `TON_Duration`; `TOF_Duration`; I/O address map | Fill-valve command (`fill_valve`); discharge-valve command (`discharge_valve`) | OpenPLC Runtime; PLC cyclic task; TON and TOF function blocks; Modbus TCP connection; Factory I/O tank scene |
| **A1** | **Acquire signals and detect start events** | Start-button signal; stop-button signal; high-level indication; high-high-level indication | I/O address map; rising-edge detection rule; input sampling rule | Start event (`start`); stop condition (`stop`); high-level condition (`LSH`); high-high-level condition (`LSHH`) | OpenPLC input image; start-edge memory; Modbus TCP interface |
| **A2** | **Evaluate filling and pause timers** | Filling-step activity | `TON_Duration`; `TOF_Duration`; TON timing semantics; TOF timing semantics; cyclic timer-execution rule | On-delay completion (`ton_q`); off-delay status (`tof_q`) | TON instance; TOF instance; PLC time base |
| **A3** | **Select the active operating step** | Start event (`start`); stop condition (`stop`); high-level condition (`LSH`); high-high-level condition (`LSHH`); on-delay completion (`ton_q`); off-delay status (`tof_q`); current-step state | Initial-step rule; transition rules; stop-priority rule; level-termination rule; high-high protection rule; exclusive-step rule | Selected-step state; filling-step activity | PLC sequence evaluator; step-state memory |
| **A4** | **Generate valve commands** | Selected-step state; stop condition (`stop`); high-level condition (`LSH`); high-high-level condition (`LSHH`) | Filling-only output rule; stop-priority rule; level-termination rule; high-high protection rule; closed-discharge rule; output address map | Fill-valve command (`fill_valve`); discharge-valve command (`discharge_valve`) | PLC output image; Modbus TCP interface; Factory I/O valve actuators |

**State feedback:** The selected-step state becomes the current-step state for the next sequence evaluation. Filling-step activity is the common input to both timers.

## 3. Child-function connections

These are the principal internal arrows of the A0 decomposition:

| Source | Arrow name | Destination |
|---|---|---|
| A1 | Start event (`start`) | A3 |
| A1 | Stop condition (`stop`) | A3, A4 |
| A1 | High-level condition (`LSH`) | A3, A4 |
| A1 | High-high-level condition (`LSHH`) | A3, A4 |
| A3 | Filling-step activity | A2 |
| A2 | On-delay completion (`ton_q`) | A3 |
| A2 | Off-delay status (`tof_q`) | A3 |
| A3 | Selected-step state | A4; step-state memory |
| Step-state memory | Current-step state | A3 |
| A4 | Fill-valve command (`fill_valve`) | A0 output boundary |
| A4 | Discharge-valve command (`discharge_valve`) | A0 output boundary |

## 4. Controls defining the sequence

IDEF0 describes functional decomposition rather than execution order. The following controls define the behavior that A2–A4 must implement.

### Step and transition rules

Conditions below use exactly the specified receptivity identifiers.

| Current step | Condition | Selected step |
|---|---|---|
| Any step | `stop` | Step 0 |
| Any step | `LSHH` | Step 0 |
| Any step | `LSH` | Step 0 |
| Step 0 | `start AND NOT stop AND NOT LSH AND NOT LSHH` | Filling step |
| Filling step | `ton_q AND NOT LSH AND NOT stop AND NOT LSHH` | Pause step |
| Pause step | `NOT tof_q AND NOT LSH AND NOT stop AND NOT LSHH` | Filling step |
| Any step | No applicable transition condition | Current step |

- **Initialization:** Step 0 is active.
- **Priority:** `stop`, `LSHH`, and `LSH` override filling and restart transitions.
- **Start-event behavior:** `start` is TRUE only on the sampled rising edge of StartCommand. A held button does not cause automatic restarting.
- **Step exclusivity:** Exactly one step is active.
- **Pause completion:** No new `start` event is needed to resume from the pause step.

### Timer rules

- TON receives filling-step activity as its IN signal. Its Q output is `ton_q`.
- TOF receives the **same** filling-step activity as its IN signal. Its Q output is `tof_q`.
- While filling, `tof_q` is TRUE.
- Leaving filling resets TON and begins the TOF off-delay. The pause continues until `tof_q` becomes FALSE.
- Both timer instances are evaluated cyclically, including during step 0 and the pause step.
- A residual TRUE `tof_q` after a stop or level termination does **not** restart filling from step 0.

### Output rules

| Operating condition | `fill_valve` | `discharge_valve` |
|---|---:|---:|
| Filling step, with `stop`, `LSH`, and `LSHH` all FALSE | TRUE | FALSE |
| Step 0 or pause step | FALSE | FALSE |
| `stop`, `LSH`, or `LSHH` TRUE | FALSE | FALSE |

## 5. Boundary I/O mapping

| Boundary arrow | Required identifier | Scene/runtime mapping |
|---|---|---|
| Start-button signal | Source of `start` | StartCommand — `%IX100.0` |
| Stop-button signal | `stop` | StopCommand — `%IX100.1` |
| High-level indication | `LSH` | LSH — `%IX100.2`, 2.4 m |
| High-high-level indication | `LSHH` | LSHH — `%IX100.3`, 2.7 m |
| Fill-valve command | `fill_valve` | FillValve — `%QX100.0` |
| Discharge-valve command | `discharge_valve` | DischargeValve — `%QX100.1`, always FALSE |

Before implementation, verify that closing the fill valve at LSH keeps the maximum subsequent level below LSHH under worst-case plant and communication delays.
