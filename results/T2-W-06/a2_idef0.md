The model below treats the PLC control logic as the system boundary. **A0** is the overall function shown on the **A-0 context diagram**; **A1–A3** are its child functions. Signal values are inputs to the logic, while operating rules and the timing parameter are controls.

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control timed tank filling** | `start`; `stop`; `LSHH` | `TimerDuration`; Initial-step rule; Start-event rule; Timer-or-overfill termination rule; Stop-priority rule; Discharge-inhibition rule | `fill_valve`; `discharge_valve` | OpenPLC Runtime; PLC scan execution; PLC timer instance; Modbus TCP connection; Factory I/O scene and I/O mapping |
| **A1** | **Manage filling-step state** | `start`; `stop`; `LSHH`; `timer_done` | Initial-step rule; Start-event rule; Timer-or-overfill termination rule; Stop-priority rule | Filling-step state | OpenPLC Runtime; Step-state memory; PLC scan execution |
| **A2** | **Measure filling-step duration** | Filling-step state | `TimerDuration`; Timer-enable and reset rules | `timer_done` | OpenPLC Runtime; PLC timer instance; Runtime time base |
| **A3** | **Set valve commands** | Filling-step state; `stop` | Initial-step output rule; Stop-priority rule; Discharge-inhibition rule | `fill_valve`; `discharge_valve` | OpenPLC Runtime; Output image; Modbus TCP connection; Factory I/O output mapping |

**Arrow and rule definitions**

- **Filling-step state:** Internal indication of step 0 (idle) or the filling step. It connects A1 to A2 and A3.
- **Initial-step rule:** Initialize in step 0.
- **Start-event rule:** In step 0, `start` enters the filling step. `start` is a one-scan press event, not the sustained button level.
- **Timer-or-overfill termination rule:** In the filling step, `timer_done` or `LSHH` returns the controller to step 0.
- **Stop-priority rule:** Whenever `stop` is TRUE, step 0 takes precedence over starting or continuing filling, and both valve commands are FALSE.
- **Timer-enable and reset rules:** Enable timing while the filling step is active; reset timing outside that step. Assert `timer_done` when the enabled timer reaches `TimerDuration`.
- **Initial-step output rule:** `fill_valve` is TRUE only while the filling step is active and `stop` is FALSE; step 0 drives no output.
- **Discharge-inhibition rule:** `discharge_valve` remains FALSE throughout this task.

**Unused scene input:** `LSH` is available in the I/O configuration but has no functional role in the stated requirements. It is therefore not connected as a functional arrow; reaching the 2.4 m target does **not** terminate this timer-based filling task.
