| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control timed tank filling** | **start**; **stop**; **LSHH** | **TimerDuration**; initial-step rule; start-to-fill rule; timer-or-high-high termination rule; stop-priority rule; discharge-inhibition rule | **fill_valve**; **discharge_valve** | OpenPLC Runtime; PLC program; timer facility; Modbus TCP interface; Factory I/O tank scene |
| **A1** | **Determine the active step** | **start**; **stop**; **LSHH**; **timer_done** | Initial step **0**; transition from step 0 to the filling step on **start**; return to step 0 on **timer_done** or **LSHH** during filling; unconditional return to step 0 while **stop** is TRUE | Active-step state | OpenPLC Runtime; step-state memory; transition logic |
| **A2** | **Time the filling step** | Active-step state | **TimerDuration**; timer activation upon entry into the filling step; timer reset outside the filling step | **timer_done** | OpenPLC Runtime; non-retentive on-delay timer |
| **A3** | **Generate valve commands** | Active-step state | **fill_valve** TRUE only during the filling step; both outputs FALSE in step 0; **discharge_valve** always FALSE | **fill_valve**; **discharge_valve** | OpenPLC Runtime; output logic; Modbus TCP output mapping |

**Model interpretation**

- **Internal arrows:** *Active-step state* connects A1 to A2 and A3. **timer_done** connects A2 back to A1; it is generated internally, not supplied as an external input to A0.
- **Input semantics:** **start** is the specified one-scan press event, not the sustained value of the physical button. **stop** has priority over starting or continuing filling.
- **Unused sensor:** **LSH** is available in the scene but has no functional role in the stated requirements. It therefore does not control a transition or stop filling in this model.
- **I/O mapping:** **start** derives from `StartCommand` at `%IX100.0`; **stop** corresponds to `StopCommand` at `%IX100.1`; **LSH** and **LSHH** correspond to `%IX100.2` and `%IX100.3`. **fill_valve** and **discharge_valve** map to `%QX100.0` and `%QX100.1`.
- **IDEF0 notation:** Formally, the context diagram is numbered **A-0**, with its single function box numbered **A0**. The decomposition of that function is diagram **A0**, containing A1–A3 above.
