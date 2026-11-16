## 1. Model scope and conventions

**A0 — Control timed tank filling**

The model covers command acquisition, step sequencing, TON/TOF timing, and valve-output generation. It does not include discharge operation.

The child functions are:
- **A1 — Acquire commands and level indications**
- **A2 — Evaluate filling timers**
- **A3 — Select the operating step**
- **A4 — Generate valve commands**

All function names are verb phrases. Arrow names below are noun phrases or the required signal identifiers.

### Modeling decisions

- The operating steps are **step 0**, **filling step**, and **pause step**. Initial operating state is **step 0**.
- `start` is the rising-edge event of `StartCommand`, lasting one PLC scan. `stop` represents the current value of `StopCommand`.
- Priority is **stop → level termination → normal sequencing**.
- `LSH` ends the cycle from either the filling step or the pause step.
- As a conservative safety addition, `LSHH` also forces step 0 and inhibits filling. This is a backup interlock, not a normal completion condition.
- TON and TOF both use **filling-step activity** as their input. TOF does not directly control the fill valve.

## 2. A0 context and child-function ICOM table

“—” means no separate arrow is required in that category.

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control timed tank filling** | `StartCommand`; `StopCommand`; `LSH`; `LSHH` | `TON_Duration`; `TOF_Duration`; **initial-state rule**; **step-transition rules**; **stop-priority rule**; **level-termination rule**; **LSHH-inhibition rule**; **discharge-inhibition rule**; **I/O mapping** | `fill_valve`; `discharge_valve` | **OpenPLC Runtime**; **PLC scan execution**; **TON timer instance**; **TOF timer instance**; **Factory I/O digital tank scene**; **Modbus TCP connection**; **Factory I/O driver** |
| **A1** | **Acquire commands and level indications** | `StartCommand`; `StopCommand`; `LSH`; `LSHH` | **I/O mapping**; **rising-edge detection rule** | `start`; `stop`; `LSH`; `LSHH` | **PLC input image**; **rising-edge memory**; **Modbus TCP connection**; **Factory I/O driver** |
| **A2** | **Evaluate filling timers** | **filling-step activity** | `TON_Duration`; `TOF_Duration`; **TON timing semantics**; **TOF timing semantics** | `ton_q`; `tof_q` | **TON timer instance**; **TOF timer instance**; **PLC time base** |
| **A3** | **Select the operating step** | **current operating state** | `start`; `stop`; `LSH`; `LSHH`; `ton_q`; `tof_q`; **initial-state rule**; **step-transition rules**; **stop-priority rule**; **level-termination rule**; **LSHH-inhibition rule** | **selected operating state**; **filling-step activity** | **PLC scan execution**; **step-state memory** |
| **A4** | **Generate valve commands** | **selected operating state** | `stop`; `LSH`; `LSHH`; **valve-assignment rules**; **discharge-inhibition rule**; **I/O mapping** | `fill_valve`; `discharge_valve` | **PLC output image**; **Modbus TCP connection**; **Factory I/O driver** |

The raw `LSH` and `LSHH` indications retain their required names through A1; A1 does not introduce alternative receptivity identifiers.

## 3. Child-diagram arrow connections

These connections define the internal arrows and boundary-arrow balancing of A0.

| Arrow | Source | Destination / ICOM role |
|---|---|---|
| `StartCommand`; `StopCommand`; `LSH`; `LSHH` | A0 input boundary | A1 inputs |
| `start`; `stop`; `LSH`; `LSHH` | A1 | A3 controls |
| `stop`; `LSH`; `LSHH` | A1 | A4 controls |
| **filling-step activity** | A3 | A2 input |
| `ton_q`; `tof_q` | A2 | A3 controls |
| **selected operating state** | A3 | A4 input; **step-state memory** |
| **current operating state** | **step-state memory** | A3 input on subsequent evaluation |
| `TON_Duration`; `TOF_Duration` | A0 control boundary | A2 controls |
| **initial-state rule**; **step-transition rules** | A0 control boundary | A3 controls |
| **stop-priority rule**; **level-termination rule**; **LSHH-inhibition rule** | A0 control boundary | A3 controls; corresponding A4 output-inhibition rules |
| **discharge-inhibition rule** | A0 control boundary | A4 control |
| **I/O mapping** | A0 control boundary | A1 and A4 controls |
| `fill_valve`; `discharge_valve` | A4 | A0 output boundary |

**Rising-edge detection rule**, **TON timing semantics**, **TOF timing semantics**, and **valve-assignment rules** are internal elaborations of the A0 control rules.

IDEF0 arrows describe functional dependencies, not execution order. The feedback through step-state memory and timer state must receive an explicit, consistent scan-order interpretation during implementation.

## 4. Sequencing rules controlled by A3

Conditions below use exactly the requested receptivity identifiers.

| Current step | Receptivity / condition | Selected step |
|---|---|---|
| Any step | `stop` | step 0 |
| Any step, with `stop` FALSE | `LSH OR LSHH` | step 0 |
| step 0 | `start AND NOT stop AND NOT LSH AND NOT LSHH` | filling step |
| filling step | `ton_q AND NOT stop AND NOT LSH AND NOT LSHH` | pause step |
| pause step | `NOT tof_q AND NOT stop AND NOT LSH AND NOT LSHH` | filling step |
| Any step | No applicable transition | Current step |

A `start` event during an active cycle has no effect. Holding `StartCommand` TRUE does not cause an automatic restart after completion or stopping; another rising edge is required.

## 5. Timing and output rules

### A2 — Evaluate filling timers

| Timer | Input activity | Required behavior |
|---|---|---|
| TON | **filling-step activity** | `ton_q` becomes TRUE after continuous filling-step activity for `TON_Duration`. Leaving the filling step resets TON. |
| TOF | **filling-step activity** | `tof_q` is TRUE while the filling step is active and remains TRUE for `TOF_Duration` after that activity becomes FALSE. The pause ends when `tof_q` becomes FALSE. |

On stop or level termination, TOF may remain TRUE during its normal off-delay. This does **not** keep the fill valve open or restart filling from step 0.

### A4 — Generate valve commands

| Selected step / overriding condition | `fill_valve` | `discharge_valve` |
|---|---:|---:|
| step 0 | FALSE | FALSE |
| filling step, with `stop`, `LSH`, and `LSHH` all FALSE | TRUE | FALSE |
| pause step | FALSE | FALSE |
| `stop OR LSH OR LSHH` | FALSE | FALSE |

### I/O mapping control

| Model signal | Scene/runtime identifier | Address |
|---|---|---|
| Raw command for `start` generation | `StartCommand` | `%IX100.0` |
| `stop` | `StopCommand` | `%IX100.1` |
| `LSH` | `LSH` | `%IX100.2` |
| `LSHH` | `LSHH` | `%IX100.3` |
| `fill_valve` | `FillValve` | `%QX100.0` |
| `discharge_valve` | `DischargeValve` | `%QX100.1` |

## 6. Safety constraint

**LSHH must never be reached** is a plant-level constraint, not something guaranteed merely by testing `LSHH` after it becomes TRUE. Normal filling must terminate at **LSH = 2.4 m**, leaving sufficient margin below **LSHH = 2.7 m** for input-update delay, PLC scan delay, valve-closing delay, and residual inflow.

The LSHH interlock is therefore a backup response to an abnormal condition. Demonstrating that LSHH is never reached requires validation of those physical and timing margins; the supplied task does not provide enough data to prove that guarantee.
