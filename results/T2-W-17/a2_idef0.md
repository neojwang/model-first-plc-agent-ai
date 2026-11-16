The model below treats the task as a **controller function**: it transforms the start event into valve commands under the specified timing, safety, and sequencing constraints. **A0** is the context function; **A1–A3** are its child functions. Signal arrows use the required identifiers.

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control timed tank filling** | `start` | `stop`; `LSHH`; `TimerDuration`; initial-step rule; filling-sequence rules; discharge-closure requirement | `fill_valve`; `discharge_valve` | OpenPLC Runtime; PLC program and state memory; Factory I/O Modbus TCP interface |
| **A1** | **Manage the filling sequence** | `start` | `stop`; `LSHH`; `timer_done`; initial-step rule; filling-sequence rules | Filling-step state | OpenPLC Runtime; sequence logic; step-state memory |
| **A2** | **Time the filling step** | Filling-step state | `TimerDuration`; timer activation and reset rules | `timer_done` | OpenPLC Runtime; timer function block |
| **A3** | **Generate valve commands** | Filling-step state | `stop`; `LSHH`; valve-command rules; discharge-closure requirement | `fill_valve`; `discharge_valve` | OpenPLC Runtime; output logic; Factory I/O Modbus TCP output mapping |

**Arrow and behavior definitions**

- **Filling-step state** identifies step 0 or the active filling step. It connects **A1 → A2** and **A1 → A3**.
- **`timer_done`** connects **A2 → A1** as a transition control. It becomes TRUE when the active filling step has lasted `TimerDuration`. Leaving that step resets the timer.
- **Initial-step and filling-sequence rules:** initialize in step 0; accept `start` to enter the filling step and start timing; return to step 0 on `timer_done` or `LSHH`. `stop` has overriding priority and returns the sequence to step 0.
- **Valve-command rules:** step 0 commands both outputs FALSE. The filling step commands `fill_valve` TRUE, subject to immediate closure on `stop` or `LSHH`. `discharge_valve` remains FALSE throughout.
- **`LSH` is intentionally not connected:** the target-level switch does not participate in any required transition or output decision for this timer-based task.
- **`start`** is the one-scan button-press event specified in the question, not the sustained value of StartCommand. The physical input and output addresses are implementation mappings, not additional functional arrows.
