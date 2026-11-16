## A0 context and decomposition

**A0 — Control timed tank filling**

The model boundary includes the PLC sequencing, filling timer, and output-command generation. The tank, sensors, valves, OpenPLC Runtime, and Factory I/O interface provide the physical or simulated means of execution.

The required signal names are retained: `start`, `stop`, `LSH`, `LSHH`, `timer_done`, `fill_valve`, and `discharge_valve`. Other arrows below name internal information, such as **Step status**.

### ICOM table

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control timed tank filling** | `start`; `stop`; `LSH`; `LSHH` | `TimerDuration`; Initial-step rule; Start-event definition; Stop-priority rule; Filling-termination rule; Discharge-inhibition rule | `fill_valve`; `discharge_valve` | OpenPLC Runtime; Factory I/O user scene; Modbus TCP connection; Operator buttons; Capacitive level switches; Fill and discharge valves |
| **A1** | **Select operating step** | `start`; `stop`; `LSH` *(unused for sequencing)*; `LSHH`; `timer_done`; Step status *(feedback)* | Initial-step rule; Start-event definition; Stop-priority rule; Filling-termination rule | Step status | PLC cyclic execution; Step-state memory |
| **A2** | **Measure filling duration** | Step status | `TimerDuration`; Timer-entry rule; Timer-reset rule | `timer_done` | PLC timer facility; PLC time base |
| **A3** | **Generate valve commands** | Step status | Initial-step rule; Fill-command rule; Discharge-inhibition rule; Same-scan update rule | `fill_valve`; `discharge_valve` | PLC output image; Modbus TCP output mapping; Factory I/O valve interfaces |

### Arrow meanings and allocations

| Arrow | Meaning / connection |
|---|---|
| `start` | One-scan event corresponding to pressing **StartCommand**, mapped from `%IX100.0`; enters A0 and A1. |
| `stop` | Current **StopCommand** level, mapped from `%IX100.1`; enters A0 and A1. |
| `LSH` | Target-level detection at **2.4 m**, mapped from `%IX100.2`; enters A0 and A1 but does **not** cause a transition or close the valve. |
| `LSHH` | Overfill-limit detection at **2.7 m**, mapped from `%IX100.3`; enters A0 and A1. |
| Step status | A1 output identifying **Step 0 — Idle** or **Step 1 — Filling**; feeds A2 and A3 and returns to A1 as state feedback. |
| `TimerDuration` | Duration parameter controlling A2. |
| `timer_done` | A2 output indicating that the filling-step timer has elapsed; feeds A1. It is internal to A0. |
| `fill_valve` | A3 output mapped to **FillValve**, `%QX100.0`; TRUE opens the fill valve. |
| `discharge_valve` | A3 output mapped to **DischargeValve**, `%QX100.1`; always FALSE for this task. |

## Control rules

These rules define the control arrows in the ICOM table.

| Control arrow | Required meaning |
|---|---|
| **Initial-step rule** | Initialize in Step 0. Both output commands are FALSE in Step 0. |
| **Start-event definition** | `start` is TRUE only for the scan associated with a new button press, not for every scan that StartCommand remains held. |
| **Stop-priority rule** | Whenever `stop` is TRUE, select Step 0 regardless of `start`, `LSHH`, or `timer_done`; both outputs are FALSE. |
| **Filling-termination rule** | While filling, either `LSHH` or `timer_done` causes a return to Step 0. `LSH` has no terminating effect. |
| **Timer-entry rule** | Start timing on entry to Step 1, coincident with the filling command. |
| **Timer-reset rule** | Reset the timer outside Step 1 so each accepted start begins a fresh timing interval. |
| **Fill-command rule** | `fill_valve` is TRUE only while the selected step is Step 1. |
| **Discharge-inhibition rule** | `discharge_valve` remains FALSE in every step. |
| **Same-scan update rule** | A stop or termination condition must affect the valve commands in the scan in which it is evaluated; no additional scan of filling is introduced by the functional decomposition. |

## Step behavior

| Current step | Condition, in priority order | Selected step | `fill_valve` | `discharge_valve` |
|---|---|---|---|---|
| Any | `stop` | Step 0 | FALSE | FALSE |
| Step 1 | `LSHH` or `timer_done` | Step 0 | FALSE | FALSE |
| Step 1 | Neither termination condition | Step 1 | TRUE | FALSE |
| Step 0 | `start` and not `LSHH`, with `stop` FALSE | Step 1 | TRUE | FALSE |
| Step 0 | Otherwise | Step 0 | FALSE | FALSE |

**Boundary interpretation:** If `LSHH` is already TRUE when `start` occurs, filling is inhibited rather than producing a one-scan valve pulse. After any return to Step 0, a new `start` event is required to fill again.

This is a functional decomposition, not a prescribed program execution order; timer completion, state selection, and output updates must preserve the same-scan behavior above.
