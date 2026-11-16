The model below treats the controller as the system boundary. **A0** is the context function; **A1–A3** are its child functions. Signal values are inputs to be processed, while sequencing rules, timing parameters, and safety requirements are controls.

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control timed tank filling** | start; stop; LSH; LSHH | TON_Duration; TOF_Duration; initial-step requirement; filling/pause sequence requirements; stop priority; LSH termination requirement; LSHH avoidance requirement; discharge_valve permanently FALSE; I/O mapping | fill_valve; discharge_valve | OpenPLC Runtime; PLC application and retained scan-to-scan state; TON and TOF function blocks; Modbus TCP connection to Factory I/O |
| **A1** | **Manage filling-cycle steps** | start; stop; LSH; LSHH; ton_q; tof_q | Initial state is step 0. start initiates the filling step from step 0. While filling, ton_q with LSH FALSE initiates the pause step. While paused, tof_q FALSE resumes filling. LSH terminates the active cycle and returns to step 0, taking precedence over timer-driven transitions. stop has highest priority and returns to step 0. LSHH must not be reached. | Step-0 activity; filling-step activity; pause-step activity | OpenPLC Runtime; step-state logic and state memory |
| **A2** | **Evaluate filling and pause delays** | Filling-step activity | TON_Duration; TOF_Duration; TON.IN equals filling-step activity; TOF.IN equals filling-step activity; TON and TOF timing semantics | ton_q; tof_q | TON function block; TOF function block; runtime time base and timer-instance memory |
| **A3** | **Generate valve commands** | Step-0 activity; filling-step activity; pause-step activity; stop | fill_valve TRUE only during the filling step and when stop is FALSE; fill_valve FALSE during step 0 and the pause step; stop forces all outputs FALSE; discharge_valve always FALSE; output-address mapping | fill_valve; discharge_valve | OpenPLC Boolean/output logic; output process image; Modbus TCP output interface |

**Interface and interpretation notes**

- `start` is the rising-edge event derived from `StartCommand` at `%IX100.0`, not the continuously held button level. `stop`, `LSH`, and `LSHH` correspond to `%IX100.1`, `%IX100.2`, and `%IX100.3`.
- `fill_valve` maps to `FillValve` at `%QX100.0`; `discharge_valve` maps to `DischargeValve` at `%QX100.1`.
- The principal internal arrows are **filling-step activity** from A1 to A2, **ton_q** and **tof_q** from A2 to A1, and the **step activities** from A1 to A3.
- **LSHH avoidance is a safety constraint, not a specified transition.** The task does not prescribe an LSHH trip action. Demonstrating that LSHH is never reached additionally requires adequate physical margin between LSH at 2.4 m and LSHH at 2.7 m, considering scan, communication, valve, and liquid-response delays.
