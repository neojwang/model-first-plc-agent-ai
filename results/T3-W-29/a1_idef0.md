## A0 context and decomposition

**A0 — Control timed tank filling**

The function fills the tank in timed phases separated by timed pauses, ends filling at **LSH (2.4 m)**, and returns to the initial state on **stop**. The discharge valve remains closed throughout.

**Modeling conventions**
- **Step 0 — Idle:** no active outputs.
- **Step 1 — Filling:** fill-valve operation permitted.
- **Step 2 — Pause:** fill valve closed while the off-delay completes.
- `start` is the one-scan rising-edge event derived from `StartCommand`; holding the button does not create repeated start events.
- `stop` is the current level of `StopCommand`.
- **Protective interpretation:** because LSHH must never be reached, `LSHH` is treated as a high-high override that closes the fill valve and returns to Step 0. Normal termination remains at `LSH`. This override is a conservative design interpretation, not a guarantee against physical overshoot.

### ICOM table

Semicolons separate individual arrows. Function names are verb phrases; arrow labels are noun phrases or the required signal identifiers.

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control timed tank filling** | StartCommand signal; StopCommand signal; LSH signal; LSHH signal | TON_Duration parameter; TOF_Duration parameter; Initial-state rule; Step-transition rules; Stop-priority rule; Level-protection rules; Output-inhibition rules; I/O address map | `fill_valve`; `discharge_valve` | OpenPLC Runtime; PLC scan execution; Modbus TCP interface; Factory I/O tank plant |
| **A1** | **Acquire and normalize command and level signals** | StartCommand signal; StopCommand signal; LSH signal; LSHH signal | I/O address map; Start-edge rule; Startup edge-initialization rule | `start`; `stop`; `LSH`; `LSHH` | Modbus TCP input interface; Input image; Rising-edge detector; Previous-command memory |
| **A2** | **Select the operating step** | `start`; `stop`; `LSH`; `LSHH`; `ton_q`; `tof_q` | Initial-state rule; Step-transition rules; Stop-priority rule; Level-protection rules | Operating-step state; Filling-step activity | Step-state memory; PLC sequence execution |
| **A3** | **Measure the filling interval** | Filling-step activity | TON_Duration parameter; TON timing semantics | `ton_q` | TON timer instance; PLC time base |
| **A4** | **Measure the post-filling delay** | Filling-step activity | TOF_Duration parameter; TOF timing semantics | `tof_q` | TOF timer instance; PLC time base |
| **A5** | **Command the tank valves** | Operating-step state; `stop`; `LSH`; `LSHH` | Output-inhibition rules; Discharge-closure rule; I/O address map | `fill_valve`; `discharge_valve` | PLC output image; Modbus TCP output interface; Factory I/O valve actuators |

### Child-function connections

These are the internal arrows of the A0 decomposition:

| Source | Arrow | Destination |
|---|---|---|
| A1 | `start` | A2 |
| A1 | `stop` | A2, A5 |
| A1 | `LSH` | A2, A5 |
| A1 | `LSHH` | A2, A5 |
| A2 | Operating-step state | A5 |
| A2 | Filling-step activity | A3, A4 |
| A3 | `ton_q` | A2 |
| A4 | `tof_q` | A2 |
| A5 | `fill_valve` | A0 boundary |
| A5 | `discharge_valve` | A0 boundary |

The A0 input and control arrows are distributed to the children shown in the ICOM table. Timer outputs and step information are **internal arrows**, not additional external plant I/O.

## Control-arrow definitions

### Initial-state rule and step-transition rules

The following table defines the transition controls used by A2. Receptivities use exactly the specified identifiers.

| Current step | Receptivity | Next step |
|---|---|---|
| Any step | `stop` | Step 0 |
| Any step | `NOT stop AND LSHH` | Step 0 |
| Any step | `NOT stop AND NOT LSHH AND LSH` | Step 0 |
| Step 0 | `NOT stop AND NOT LSHH AND NOT LSH AND start` | Step 1 |
| Step 1 | `NOT stop AND NOT LSHH AND NOT LSH AND ton_q` | Step 2 |
| Step 2 | `NOT stop AND NOT LSHH AND NOT LSH AND NOT tof_q` | Step 1 |
| Any step | No applicable transition | Current step |

**Priority:** `stop` overrides everything; level termination overrides timer-driven transitions. A new `start` event is required after a return to Step 0.

### Timer controls

| Timer function | Input condition | Preset | Output behavior |
|---|---|---|---|
| A3 — TON | Filling-step activity | TON_Duration | `ton_q` becomes TRUE after uninterrupted filling-step activity for the preset duration; it resets when that activity becomes FALSE. |
| A4 — TOF | Filling-step activity | TOF_Duration | `tof_q` is TRUE during filling-step activity and remains TRUE for the preset duration after that activity becomes FALSE. |

Both timer functions must be evaluated cyclically, including during Step 0 and Step 2. A residual TRUE `tof_q` after a stop or level termination **does not authorize a restart**; only Step 2 uses `NOT tof_q` to resume filling.

### Output-inhibition rules

| Condition | `fill_valve` | `discharge_valve` |
|---|---|---|
| Step 0 | FALSE | FALSE |
| Step 1, with `NOT stop AND NOT LSH AND NOT LSHH` | TRUE | FALSE |
| Step 2 | FALSE | FALSE |
| `stop OR LSH OR LSHH`, regardless of step | FALSE | FALSE |

## I/O boundary mapping

| Model signal | Plant/runtime tag | Address | Meaning |
|---|---|---|---|
| `start` | StartCommand | `%IX100.0` | One-scan rising-edge event derived from the input |
| `stop` | StopCommand | `%IX100.1` | Stop request |
| `LSH` | LSH | `%IX100.2` | Level detection at 2.4 m |
| `LSHH` | LSHH | `%IX100.3` | High-high level detection at 2.7 m |
| `fill_valve` | FillValve | `%QX100.0` | Fill-valve command |
| `discharge_valve` | DischargeValve | `%QX100.1` | Discharge-valve command, permanently FALSE |

**Physical validation requirement:** avoiding LSHH depends on the 0.3 m margin above LSH, inflow rate, valve closing time, scan time, and communication delay. Those characteristics must be checked before claiming that LSHH can never be reached.
