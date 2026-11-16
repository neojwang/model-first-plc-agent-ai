The model below treats command and sensor information as **inputs transformed into control decisions**, and the sequencing rules and timer setting as **controls**. A0 is the context function; A1–A3 are its child functions.

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control timed tank filling** | `start`; `stop`; `LSHH` | `TimerDuration`; initial-step requirement; filling-sequence rules; stop priority; discharge-valve prohibition | `fill_valve`; `discharge_valve` | OpenPLC Runtime; Factory I/O digital tank scene with capacitive level switches; Modbus TCP connection and configured I/O mapping |
| **A1** | **Determine the active filling step** | `start`; `stop`; `LSHH`; `timer_done` from A2 | Initial state is step 0; `stop` forces step 0 from every state; `start` in step 0 initiates the filling step; `LSHH` or `timer_done` terminates the filling step and returns to step 0 | Active-step state: step 0 or filling step | OpenPLC cyclic execution; step-state storage |
| **A2** | **Time the filling step** | Active-step state from A1 | `TimerDuration`; timer runs only during the filling step; timer resets outside the filling step | `timer_done` to A1 | OpenPLC timer function and runtime time base |
| **A3** | **Command the tank valves** | Active-step state from A1 | `fill_valve` is TRUE only in the filling step and FALSE in step 0; `discharge_valve` is always FALSE | `fill_valve`; `discharge_valve` | OpenPLC output logic; Modbus TCP output mapping; Factory I/O valve actuators |

**Interpretation and boundary notes**

- `start` is the **one-scan button-press event**, not the sustained value of `StartCommand`. `stop` is the current value of `StopCommand`.
- `LSH` is available in the plant but is **not used by the specified control logic**. In particular, reaching 2.4 m does not terminate filling. Consequently, it has no functional arrow in this model.
- The timer and step-state feedback are internal arrows: **A1 → A2** carries the active-step state, and **A2 → A1** carries `timer_done`. **A1 → A3** carries the active-step state.
- State decisions precede output assignment in each scan. Thus `stop` forces both outputs FALSE, and `LSHH` or `timer_done` closes `fill_valve` when it terminates the filling step. A termination condition takes precedence over starting or continuing filling; a new filling cycle requires a subsequent `start` event.
- External output mappings are `fill_valve` → `FillValve` at `%QX100.0` and `discharge_valve` → `DischargeValve` at `%QX100.1`.
