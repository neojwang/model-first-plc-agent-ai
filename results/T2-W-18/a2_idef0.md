The model below treats command and sensor signals as **inputs**, the operating rules and time setting as **controls**, and the PLC execution facilities as **mechanisms**. The context function is **A0**; its decomposition contains **A1–A3**.

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control timed tank filling** | **start**; **stop**; **LSHH** | **TimerDuration**; initial-step rule; start-triggered filling rule; timer-or-high-high termination rule; stop-priority rule; discharge-inhibition rule | **fill_valve**; **discharge_valve** | OpenPLC Runtime; PLC application; Modbus TCP connection; Factory I/O tank scene and mapped I/O |
| **A1** | **Determine the operating step** | **start**; **stop**; **LSHH**; **timer_done** | Initial step **0**; transition from step 0 to the filling step on **start**; return to step 0 on **timer_done** or **LSHH**; unconditional return to step 0 while **stop** is TRUE | **Operating-step state** | OpenPLC cyclic execution; step-state memory |
| **A2** | **Measure the filling interval** | **Operating-step state** | **TimerDuration**; timer activation on entry to the filling step; timer reset outside the filling step | **timer_done** | PLC timer function block; PLC time base |
| **A3** | **Generate valve commands** | **Operating-step state**; **stop** | **fill_valve** TRUE only while the filling step is active and **stop** is FALSE; all outputs FALSE in step 0; **discharge_valve** always FALSE | **fill_valve**; **discharge_valve** | PLC output logic; mapped output image; Modbus TCP output transfer |

**Model notes**

- **Internal arrows:** **Operating-step state** connects A1 to A2 and A3; **timer_done** connects A2 back to A1. Neither is an external context input.
- **start** is the specified one-scan press event, not a continuously held command.
- **stop** has priority over starting or continuing filling. Timer expiry and **LSHH** both terminate filling; neither termination requires the other.
- **LSH** is available in the scene but is **not used by this task’s control logic**. It therefore has no functional connection in this model; it must not be interpreted as a filling cutoff.
- The valve outputs are Boolean commands. Physical liquid flow is part of the simulated plant, not an additional output of this controller function.
