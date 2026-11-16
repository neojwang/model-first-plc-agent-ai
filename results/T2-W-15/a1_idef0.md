## A0 context and decomposition

**A0 — Control timed tank filling**

The function accepts a momentary start event, fills the tank for at most `TimerDuration`, and returns to the initial idle step when the timer expires, an overfill is detected, or a stop is requested.

The child functions are:

- **A1 — Determine filling-step activity**
- **A2 — Measure filling-step duration**
- **A3 — Drive tank valves**

Function names are verb phrases. Arrow names below are noun phrases or the exact signal identifiers required by the task.

### Signal interpretation

| Model identifier | Plant mapping | Meaning |
|---|---|---|
| `start` | Rising edge of `StartCommand`, `%IX100.0` | TRUE only during the scan in which the button is pressed |
| `stop` | `StopCommand`, `%IX100.1` | Maintained stop condition |
| `LSH` | `%IX100.2` | Liquid detected at 2.4 m; **not a termination condition in this task** |
| `LSHH` | `%IX100.3` | Liquid detected at the 2.7 m overfill limit |
| `timer_done` | Internal filling-step timer | Filling duration has elapsed |
| `fill_valve` | `FillValve`, `%QX100.0` | TRUE opens the fill valve |
| `discharge_valve` | `DischargeValve`, `%QX100.1` | Always FALSE |

`LSH` is an available plant signal but has no functional use in the specified control. It is therefore not connected to a child function or treated as a stop condition in this model.

## ICOM table

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control timed tank filling** | `start`; `stop`; `LSHH` | `TimerDuration`; initial-step rule; stop-priority rule; filling-termination rule; discharge-inhibition rule | `fill_valve`; `discharge_valve` | OpenPLC Runtime; scan execution service; start-event detection service; timer service; Modbus TCP interface; Factory I/O tank scene and mapped devices |
| **A1** | **Determine filling-step activity** | `start`; `stop`; `LSHH`; `timer_done` | Initial-step rule; step-transition rules; stop-priority rule | Filling-step status | OpenPLC Runtime; step-state storage; scan execution service |
| **A2** | **Measure filling-step duration** | Filling-step status | `TimerDuration`; timer-enable rule; timer-reset rule | `timer_done` | OpenPLC Runtime; timer service |
| **A3** | **Drive tank valves** | Filling-step status; `stop`; `LSHH`; `timer_done` | Initial-step output rule; fill-valve permission rule; discharge-inhibition rule | `fill_valve`; `discharge_valve` | OpenPLC output image; Modbus TCP interface; Factory I/O valve devices |

### Control-arrow definitions

| Control arrow | Definition |
|---|---|
| **Initial-step rule** | Step 0 is the initial state. |
| **Step-transition rules** | A valid `start` in step 0 selects the filling step. `timer_done` or `LSHH` returns the filling step to step 0. |
| **Stop-priority rule** | `stop` overrides `start` and every other condition, selects step 0, and forces both outputs FALSE. |
| **Filling-termination rule** | Filling ends on the first occurrence of `timer_done` or `LSHH`. |
| **Timer-enable rule** | The timer runs only while the filling step is active. |
| **Timer-reset rule** | The timer resets in step 0, so every new filling operation receives a fresh timing interval. |
| **Initial-step output rule** | Step 0 commands both outputs FALSE. |
| **Fill-valve permission rule** | `fill_valve` is TRUE only during the filling step and only while `stop`, `LSHH`, and `timer_done` are all FALSE. |
| **Discharge-inhibition rule** | `discharge_valve` is always FALSE. |

## Child-function arrow connections

| Arrow | Source | Destination |
|---|---|---|
| `start` | A0 input boundary | A1 input |
| `stop` | A0 input boundary | A1 and A3 inputs |
| `LSHH` | A0 input boundary | A1 and A3 inputs |
| **Filling-step status** | A1 output | A2 and A3 inputs |
| `timer_done` | A2 output | A1 and A3 inputs |
| `TimerDuration` | A0 control boundary | A2 control |
| `fill_valve` | A3 output | A0 output boundary |
| `discharge_valve` | A3 output | A0 output boundary |

The rules in the ICOM table enter the corresponding functions as **controls**. Runtime services and plant interfaces enter as **mechanisms**.

## Behavioral constraints

These constraints define the model’s intended behavior without prescribing PLC code or execution order:

| Current condition | Required result |
|---|---|
| Initialization | Step 0; timer reset; both outputs FALSE |
| `stop` TRUE | Step 0; timer reset; both outputs FALSE, regardless of other signals |
| Step 0, `start` TRUE, `stop` FALSE, `LSHH` FALSE | Enter the filling step; begin timing; open the fill valve |
| Step 0, `LSHH` TRUE | Remain in step 0; do not open the fill valve |
| Filling step, neither `timer_done` nor `LSHH` nor `stop` TRUE | Continue timing and filling |
| Filling step, `timer_done` or `LSHH` TRUE | Close the fill valve and return to step 0 |
| Any state, `LSH` TRUE | No change attributable to `LSH` |
| Any state | Keep `discharge_valve` FALSE |

**Event and priority interpretation:** A held Start button does not cause automatic restarting because `start` is a one-scan event. A start event coincident with `stop` or an active `LSHH` is not queued; a new press is required after the blocking condition clears.
