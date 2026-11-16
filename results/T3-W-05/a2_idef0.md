### IDEF0 functional model

**Scope:** the controller for timed tank filling, rather than the physical movement of liquid. Accordingly, commands and sensor observations are modeled as **inputs**, sequencing rules and timer settings as **controls**, and the PLC/runtime and communication facilities as **mechanisms**.

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control timed tank filling** | start; stop; LSH; LSHH | TON_Duration; TOF_Duration; initial-step requirement; filling-and-pause sequence; stop priority; LSH termination requirement; LSHH avoidance requirement; discharge-valve prohibition | fill_valve; discharge_valve | OpenPLC Runtime; PLC control program; TON and TOF function blocks; Modbus TCP connection; Factory I/O tank scene |
| **A1** | **Determine operating step** | start; stop; LSH; LSHH; ton_q; tof_q; operating-step feedback | Initial step 0; stop priority; LSH termination priority; filling-to-pause condition; pause-to-filling condition; LSHH avoidance requirement | Operating-step state; filling-step activity | OpenPLC Runtime; step-sequencing logic; step-state memory |
| **A2** | **Time filling activity** | Filling-step activity | TON_Duration; TON behavior; cyclic execution requirement | ton_q | OpenPLC Runtime; TON function-block instance |
| **A3** | **Time filling inactivity** | Filling-step activity | TOF_Duration; TOF behavior; cyclic execution requirement | tof_q | OpenPLC Runtime; TOF function-block instance |
| **A4** | **Set valve commands** | Operating-step state; stop | Filling-step output assignment; step-0 and pause output prohibitions; stop priority; discharge-valve prohibition | fill_valve; discharge_valve | OpenPLC Runtime; output-assignment logic; Modbus TCP output mapping |

### Functional meaning of the decomposition

- **A1 — Determine operating step**
  - Initialization selects **step 0**.
  - **stop** selects step 0 from any step.
  - In step 0, **start** initiates filling, provided **stop** and **LSH** are FALSE.
  - During an active filling cycle, **LSH** terminates the cycle and selects step 0, including if detection occurs during a pause.
  - In the filling step, **ton_q AND NOT LSH** selects the pause step.
  - In the pause step, **NOT tof_q**, with **stop** and **LSH** FALSE, selects the filling step.
  - Operating-step feedback represents the retained state, not an additional external plant input.

- **A2 — Time filling activity**
  - TON receives filling-step activity as its `IN`.
  - **ton_q** becomes TRUE after continuous filling-step activity for **TON_Duration**.
  - Leaving the filling step resets TON according to standard TON behavior.

- **A3 — Time filling inactivity**
  - TOF also receives filling-step activity as its `IN`.
  - **tof_q** is TRUE while filling is active and remains TRUE for **TOF_Duration** after filling is left.
  - During a pause, **tof_q** becoming FALSE permits A1 to resume filling. The timer does not independently initiate a filling cycle from step 0.

- **A4 — Set valve commands**
  - **fill_valve** is TRUE only in the filling step and only when **stop** is FALSE.
  - **discharge_valve** is always FALSE.
  - Step 0 and the pause step command both outputs FALSE.

**Interface interpretation:** **start** is the one-scan press event derived from `StartCommand`; **stop** is the level of `StopCommand`. **LSH** and **LSHH** retain their specified names. The output arrows **fill_valve** and **discharge_valve** map to `FillValve` at `%QX100.0` and `DischargeValve` at `%QX100.1`, respectively.

**Safety qualification:** The task requires that **LSHH** never be reached, but specifies no distinct transition or trip action triggered by **LSHH**. This model therefore retains it as an available observation and does **not** invent an LSHH trip. Avoidance relies on terminating filling at **LSH**; proving that the liquid cannot subsequently reach LSHH also requires physical assumptions about sensing, scan time, valve closure, and residual inflow.
