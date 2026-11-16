## A0 context and decomposition

**Model boundary:** the OpenPLC controller, including input sampling, start-event detection, step control, timer operation, and output assignment. The tank, switches, valves, and Factory I/O simulation are outside this boundary.

Physical I/O arrows are identified by their hardware tags. Internal receptivities and output commands use exactly the required vocabulary: `start`, `stop`, `LSH`, `LSHH`, `timer_done`, `fill_valve`, and `discharge_valve`.

### IDEF0 ICOM table

Each semicolon-separated entry is an arrow. Function names are verb phrases; arrow names are noun phrases.

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control timed tank filling** | Start-button signal (`StartCommand`, `%IX100.0`); Stop-button signal (`StopCommand`, `%IX100.1`); Target-level signal (`LSH`, `%IX100.2`); Overfill-level signal (`LSHH`, `%IX100.3`) | `TimerDuration`; Initial-step rule; Start-event rule; Stop-priority rule; Timer-or-overfill termination rule; Discharge-inhibition rule; I/O address map | `fill_valve` (`FillValve`, `%QX100.0`); `discharge_valve` (`DischargeValve`, `%QX100.1`) | OpenPLC Runtime; PLC scan cycle; Modbus TCP interface to Factory I/O |
| **A1** | **Acquire commands and level conditions** | Start-button signal (`StartCommand`, `%IX100.0`); Stop-button signal (`StopCommand`, `%IX100.1`); Target-level signal (`LSH`, `%IX100.2`); Overfill-level signal (`LSHH`, `%IX100.3`) | Start-event rule; I/O address map; Input-sampling convention | `start`; `stop`; `LSH`; `LSHH` | PLC input image; Rising-edge memory; Modbus TCP interface |
| **A2** | **Manage filling-step transitions** | `start`; `stop`; `LSH` (observation only); `LSHH`; `timer_done` | Initial-step rule; Stop-priority rule; Timer-or-overfill termination rule; Step-transition rules | Step status | PLC sequence logic; Step-state memory |
| **A3** | **Measure filling-step duration** | Step status | `TimerDuration`; Timer-reset rule; Timer-completion rule | `timer_done` | PLC on-delay timer; Runtime time base |
| **A4** | **Assign valve commands** | Step status | Idle-output rule; Filling-output rule; Discharge-inhibition rule; I/O address map | `fill_valve` (`FillValve`, `%QX100.0`); `discharge_valve` (`DischargeValve`, `%QX100.1`) | PLC output image; Modbus TCP interface |

### Child-function connections

- The four physical input signals enter **A1**.
- **A1 → A2:** `start`, `stop`, `LSH`, and `LSHH`.
- **A2 → A3:** Step status.
- **A3 → A2:** `timer_done`.
- **A2 → A4:** Step status.
- **A4 → A0 boundary:** `fill_valve` and `discharge_valve`.

`timer_done` is an **internal arrow**, not an external input to A0. `LSH` is acquired but has no effect on transitions or outputs in this timer-based task.

## Behavioral controls

These rules define the controls referenced in the ICOM table.

| Control arrow | Definition |
|---|---|
| **Initial-step rule** | Initialize the sequence in step 0, the idle step. |
| **Start-event rule** | `start` is TRUE only for the scan detecting a FALSE-to-TRUE transition of `StartCommand`. Holding the button does not generate repeated start events. |
| **Input-sampling convention** | Evaluate commands and level conditions from the PLC input image for the current scan. |
| **Stop-priority rule** | Whenever `stop` is TRUE, select step 0 regardless of `start`, timer status, or level conditions. |
| **Step-transition rules** | From step 0, accept `start` only when `stop` and `LSHH` are FALSE, and enter the filling step. While filling, remain there until a termination condition occurs. Start events during filling do not restart the timer. |
| **Timer-or-overfill termination rule** | During filling, either `timer_done` or `LSHH` returns the sequence to step 0. An already-active `LSHH` prevents entry into filling. |
| **Timer-reset rule** | Reset the filling timer whenever step 0 is active. Start timing upon entry into the filling step. |
| **Timer-completion rule** | Assert `timer_done` when the filling timer reaches `TimerDuration`. Completion is recognized at PLC scan resolution. |
| **Idle-output rule** | In step 0, `fill_valve` and `discharge_valve` are FALSE. |
| **Filling-output rule** | In the filling step, `fill_valve` is TRUE. Apply outputs from the resolved step status so a stop or termination condition closes the valve in that scan’s output update. |
| **Discharge-inhibition rule** | `discharge_valve` remains FALSE in every step. |

**Restart behavior:** after timer completion, overfill detection, or a stop, a new `start` event is required. Releasing `stop` or clearing `LSHH` alone does not restart filling.
