| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control timed tank filling** | `start`; `stop`; `LSHH` | `TimerDuration`; initial-step rule; filling termination rule; stop-priority rule; discharge-valve prohibition | `fill_valve`; `discharge_valve` | OpenPLC Runtime; PLC application and scan cycle; Modbus TCP connection; Factory I/O tank, level switches, and valve actuators |
| **A1** | **Manage the filling sequence** | `start`; `stop`; `LSHH`; `timer_done` | Initial state: step 0; transition from step 0 to the filling step on `start`; return to step 0 on `timer_done` or `LSHH`; overriding return to step 0 whenever `stop` is TRUE | Filling-step status | PLC sequence logic; step-state memory; OpenPLC Runtime |
| **A2** | **Time the filling step** | Filling-step status | `TimerDuration`; timer activation on entry to the filling step; timer reset outside the filling step | `timer_done` | PLC timer instance; OpenPLC Runtime time base |
| **A3** | **Command the tank valves** | Filling-step status | Step-0 all-outputs-FALSE rule; filling-step fill-valve rule; `stop` override; discharge-valve prohibition | `fill_valve`; `discharge_valve` | PLC output logic; `%QX100.0` and `%QX100.1` output channels; Modbus TCP connection; Factory I/O valve actuators |

**Model interpretation**

- **Hierarchy:** A0 is the context function requested here; A1–A3 are its child functions. In strict FIPS 183 diagram notation, the single-box context diagram is **A-0**, containing function **A0**; its decomposition diagram is **A0**.
- **Internal arrows:** *Filling-step status* connects A1 to A2 and A3. `timer_done` connects A2 back to A1. These arrows are internal and therefore do not appear at the context boundary.
- **Signal meanings:** `start` is the one-scan press event derived from `StartCommand` at `%IX100.0`, not a continuously held start signal. `stop` corresponds to `StopCommand` at `%IX100.1`; `LSHH` corresponds to `%IX100.3`.
- **Unused signal:** `LSH` at `%IX100.2` is available in the plant configuration but has no specified role in this task. It is therefore not assigned a functional arrow or used as a filling termination condition.
- **Output behavior:** `fill_valve` is TRUE only while the filling step is active. `discharge_valve` remains FALSE throughout. `stop` takes precedence over a simultaneous `start` or any other condition.
