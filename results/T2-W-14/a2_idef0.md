**Model boundary:** the function being modeled is the **tank-filling controller**, not the physical movement of liquid. Command and sensor signals are treated as inputs; operating requirements and the duration parameter are controls. The PLC runtime and its I/O connection are mechanisms.

The table uses **A0** for the requested context function and **A1–A3** for its decomposition.

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control timed tank filling** | `start`; `stop`; `LSHH` | `TimerDuration`; initial-step requirement; filling-start requirement; timer-or-overfill termination requirement; stop-priority requirement; discharge-valve inhibition requirement | `fill_valve`; `discharge_valve` | OpenPLC Runtime; Factory I/O tank scene; Modbus TCP I/O connection |
| **A1** | **Manage the filling step** | `start`; `stop`; `LSHH`; `timer_done` | Initial state is step 0; `start` activates the filling step from step 0; `timer_done` or `LSHH` terminates filling; `stop` overrides other conditions and returns the controller to step 0 | Filling-step state | OpenPLC Runtime; step-state memory |
| **A2** | **Time the filling step** | Filling-step state | `TimerDuration`; timer starts on entry to the filling step; timer resets when the filling step is inactive | `timer_done` | OpenPLC Runtime; timer instance; runtime time base |
| **A3** | **Generate valve commands** | Filling-step state; `stop` | `fill_valve` is TRUE only during the filling step; step 0 drives no output; `stop` forces all outputs FALSE; `discharge_valve` remains FALSE | `fill_valve`; `discharge_valve` | OpenPLC Runtime; output image; Modbus TCP output mapping |

### Arrow and interpretation notes

- **Internal connections:** A1 supplies **Filling-step state** to A2 and A3. A2 supplies `timer_done` to A1. The state and timer mechanisms retain information between controller scans.
- **`start`** is the specified one-scan press event derived from `StartCommand`, not a continuously asserted start level. **`stop`** represents the current level of `StopCommand`.
- **`LSH` is deliberately absent from the functional arrows.** It is available at `%IX100.2`, but none of the stated requirements uses it to control this timer-based task. It must not be substituted for `LSHH` as the filling cutoff.
- **`timer_done` is internal**, not an external plant input. Its name is preserved exactly as required.
- The physical bindings are `start` from `StartCommand` at `%IX100.0`, `stop` from `StopCommand` at `%IX100.1`, `LSHH` at `%IX100.3`, `fill_valve` to `%QX100.0`, and `discharge_valve` to `%QX100.1`.
- In strict FIPS 183 diagram notation, the **context diagram is A-0**, containing the single box numbered **A0**; the decomposition diagram is **A0**, containing **A1–A3**.
