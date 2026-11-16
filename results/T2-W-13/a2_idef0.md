The model below covers the **controller’s filling-cycle logic**, rather than the physical movement of liquid. **A0** is the context function; **A1–A3** are its child functions. The signal names specified in the task are preserved exactly.

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control timed tank filling** | **start**; **stop**; **LSHH** | **TimerDuration**; initial-step rule; start-event rule; timer-or-overfill termination rule; stop-priority rule; discharge-valve inhibition rule | **fill_valve**; **discharge_valve** | OpenPLC Runtime; PLC program and scan execution; Modbus TCP connection; Factory I/O tank scene and mapped I/O |
| **A1** | **Manage the filling sequence** | **start**; **stop**; **LSHH**; **timer_done** | Initial state: step 0; filling entry on **start**; filling termination on **timer_done** or **LSHH**; overriding return to step 0 on **stop** | Filling-step status | PLC sequence logic; sequence-state memory |
| **A2** | **Time the filling interval** | Filling-step status | **TimerDuration**; timer-start rule on filling-step entry; timer-reset rule outside the filling step | **timer_done** | PLC timer function; PLC time base |
| **A3** | **Generate valve commands** | Filling-step status | **fill_valve** activation rule during the filling step; all-outputs-FALSE rule in step 0; permanent **discharge_valve** inhibition rule | **fill_valve**; **discharge_valve** | PLC output logic; mapped output image; Modbus TCP output interface |

### Arrow and behavior clarifications

- **Filling-step status** is an internal noun-phrase arrow from **A1** to **A2** and **A3**. It identifies whether the controller is in step 0 or the filling step.
- **timer_done** is an internal feedback arrow from **A2** to **A1**, not an external input to **A0**.
- **start** is the stipulated one-scan press event, not the continuously held value of `StartCommand`.
- **stop** has highest priority. Its assertion makes **A1** select step 0 and **A3** produce **fill_valve = FALSE** and **discharge_valve = FALSE** in that scan.
- During filling, either **timer_done** or **LSHH** terminates filling and returns the sequence to step 0. A high **LSHH** must not permit an opening pulse if it coincides with **start**.
- **LSH** is available at the plant interface but has **no specified control role** in this task. It is therefore not a functional arrow in this model; in particular, it does not terminate filling.
- **discharge_valve** remains **FALSE** in every state.
