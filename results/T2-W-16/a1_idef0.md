## 1. Model scope and conventions

The model controls a **two-step filling cycle**:

- **Step 0 — Idle:** both outputs are FALSE.
- **Step 1 — Filling:** the fill valve is open and the filling timer runs.

As requested, the overall context function is labeled **A0**, with child functions **A1–A3**. In strict FIPS 183 diagram numbering, the context diagram is normally **A-0**, containing function box A0; the decomposition diagram is A0.

All function names below are verb phrases. All arrows are noun phrases or the required signal identifiers.

### Signal vocabulary and physical mapping

| Model identifier | Physical tag / address | Meaning |
|---|---|---|
| `start` | Press event derived from `StartCommand`, `%IX100.0` | TRUE only during the scan in which a new button press is detected |
| `stop` | `StopCommand`, `%IX100.1` | Stop request; active whenever TRUE |
| `LSH` | `LSH`, `%IX100.2` | Liquid detection at 2.4 m |
| `LSHH` | `LSHH`, `%IX100.3` | Liquid detection at the 2.7 m overfill limit |
| `timer_done` | Internal timer result | Elapsed-time indication for the filling step |
| `fill_valve` | `FillValve`, `%QX100.0` | TRUE opens the fill valve |
| `discharge_valve` | `DischargeValve`, `%QX100.1` | Always FALSE in this task |

**Scope clarification:** `LSH` is available in the plant configuration but is not used by the specified control logic. It therefore has no functional arrow in this model. In particular, reaching 2.4 m does **not** terminate filling.

The model boundary uses the prescribed `start` event rather than the raw button level. Input acquisition must therefore provide press-event detection.

## 2. IDEF0 ICOM model

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control timed tank filling** | `start`; `stop`; `LSHH` | `TimerDuration`; initial-step rule; stop-priority rule; filling-termination rule; discharge-inhibition rule; scan-execution semantics | `fill_valve`; `discharge_valve` | OpenPLC Runtime; PLC state storage; PLC timer service; Factory I/O Modbus TCP interface; customized digital tank scene; input-event detection |
| **A1** | **Determine filling-step status** | `start`; `stop`; `LSHH`; `timer_done` | Initial-step rule; stop-priority rule; filling-termination rule; scan-execution semantics | Filling-step status; idle-step status | OpenPLC Runtime; PLC state storage |
| **A2** | **Measure filling-step duration** | Filling-step status | `TimerDuration`; timer-reset rule; scan-execution semantics | `timer_done` | OpenPLC Runtime; PLC timer service |
| **A3** | **Command tank valves** | Filling-step status; idle-step status; `stop`; `LSHH`; `timer_done` | Idle-output rule; stop-priority rule; filling-termination rule; discharge-inhibition rule | `fill_valve`; `discharge_valve` | OpenPLC Runtime; Factory I/O Modbus TCP interface; fill-valve actuator; discharge-valve actuator |

### Control-arrow definitions

| Control arrow | Definition |
|---|---|
| Initial-step rule | Initialization selects step 0, with no active output. |
| Stop-priority rule | `stop` overrides `start` and all filling activity; step 0 and both outputs FALSE are required. |
| Filling-termination rule | `LSHH` or `timer_done` terminates filling, whichever occurs first. A TRUE `LSHH` also prevents an effective fill command on a start scan. |
| Timer-reset rule | The timer runs only during the filling step and resets when that step is inactive. Each new filling cycle receives a fresh timing interval. |
| Idle-output rule | Both outputs are FALSE in step 0. |
| Discharge-inhibition rule | `discharge_valve` is always FALSE. |
| Scan-execution semantics | Step decisions, timer evaluation, and output commands are coordinated so that a detected stop or termination condition suppresses filling in the applicable control scan. |

## 3. Child-function connections

The decomposition is functional, not a claim that each function executes exactly once in the order shown.

| Arrow | Source | Destination |
|---|---|---|
| `start` | A0 input boundary | A1 |
| `stop` | A0 input boundary | A1, A3 |
| `LSHH` | A0 input boundary | A1, A3 |
| `TimerDuration` | A0 control boundary | A2 |
| Filling-step status | A1 | A2, A3 |
| Idle-step status | A1 | A3 |
| `timer_done` | A2 | A1, A3 |
| `fill_valve` | A3 | A0 output boundary |
| `discharge_valve` | A3 | A0 output boundary |

The `timer_done` connection from A2 to A1 is an internal feedback arrow: elapsed time influences the selection of the active step.

## 4. Behavioral constraints captured by the model

| Current condition | Required behavior |
|---|---|
| Initialization | Select step 0; command both outputs FALSE. |
| `stop` is TRUE | Select step 0 immediately in the control scan; command both outputs FALSE; reset the filling timer. |
| Step 0, `start` is TRUE, and `LSHH` is FALSE | Enter the filling step, start a fresh timer interval, and command `fill_valve` TRUE unless an immediate timer completion applies. |
| Filling step, with neither `LSHH` nor `timer_done` TRUE | Continue timing and keep `fill_valve` TRUE. |
| Filling step, with `LSHH` or `timer_done` TRUE | Command `fill_valve` FALSE, return to step 0, and reset the filling timer. |
| `start` occurs during filling | Do not restart or extend the timer. |
| `start` coincides with `stop` | Stop takes priority; remain in or return to step 0. |
| `start` coincides with `LSHH` | Keep both outputs FALSE; remain in step 0. |
| `LSH` changes state | No effect on step selection, timing, or outputs. |
| Any operating condition | Keep `discharge_valve` FALSE. |

**Restart behavior:** After termination, a held StartCommand does not automatically start another cycle. A new `start` event is required.
