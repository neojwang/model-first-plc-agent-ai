The model below treats the **PLC control function** as the system boundary. Its inputs are command and level signals; its outputs are valve commands. The simulated tank, sensors, PLC runtime, and communications provide the execution environment.

**A0** is the context function requested; **A1–A4** are its child functions. Internal arrows such as “Filling-step activity” are shared between child functions and do not cross the A0 boundary.

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control timed tank filling** | `start`; `stop`; `LSH`; `LSHH` | `TON_Duration`; `TOF_Duration`; initial-step rule; filling/pause sequence rules; stop priority; level-completion rule; prohibition on reaching LSHH; `discharge_valve` FALSE requirement; I/O mapping | `fill_valve`; `discharge_valve` | OpenPLC Runtime; Factory I/O tank scene; Modbus TCP connection; command buttons; level switches; valve actuators; TON and TOF function blocks |
| **A1** | **Manage the filling sequence** | `start`; `stop`; `LSH`; `LSHH`; `ton_q`; `tof_q` | Initial state: step 0; start acceptance in step 0; transition from filling to pause on `ton_q` AND NOT `LSH`; transition from pause to filling on NOT `tof_q`; return to step 0 on `LSH`; overriding return to step 0 on `stop`; LSHH avoidance constraint | Filling-step activity; current-step state; high-high limit status | PLC cyclic task; sequence-state memory; transition logic |
| **A2** | **Time the filling phase** | Filling-step activity | `TON_Duration`; TON semantics; `IN` assignment to filling-step activity | `ton_q` | TON function-block instance; PLC time base |
| **A3** | **Time the filling pause** | Filling-step activity | `TOF_Duration`; TOF semantics; `IN` assignment to filling-step activity | `tof_q` | TOF function-block instance; PLC time base |
| **A4** | **Command the tank valves** | Filling-step activity; current-step state | Filling-only valve-opening rule; step-0 and pause output rules; overriding `stop` condition; level-completion condition `LSH`; `discharge_valve` FALSE requirement; output-address mapping | `fill_valve`; `discharge_valve` | PLC output logic; output image; Modbus TCP driver; simulated valve actuators |

### Interpretation and boundary details

- **Signal names:** `start` is the one-scan rising-edge event derived from `StartCommand` at `%IX100.0`; `stop` is the state of `StopCommand` at `%IX100.1`. `LSH` and `LSHH` are mapped to `%IX100.2` and `%IX100.3`. `fill_valve` and `discharge_valve` are mapped to `%QX100.0` and `%QX100.1`.
- **Sequence priority:** `stop` overrides filling and pause operation. `LSH` ends an active filling cycle rather than allowing a timer-driven pause or restart. In step 0 and pause, both valve commands are FALSE; during filling, only `fill_valve` is TRUE.
- **Timer coupling:** Both timer inputs use the same filling-step activity. Thus, `ton_q` becomes TRUE after continuous filling for `TON_Duration`, while `tof_q` remains TRUE for `TOF_Duration` after filling ends.
- **LSHH limitation:** The task specifies that LSHH must never be reached, but does **not** prescribe an LSHH-triggered transition. The model therefore includes high-high monitoring and the avoidance constraint without inventing an additional trip sequence. Assurance that LSHH is never reached also depends on the plant’s flow rate, scan/communication latency, and valve response after LSH detection.
