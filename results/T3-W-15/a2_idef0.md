### Functional scope

**A0** models the controller, rather than the physical transfer of liquid. Its inputs are command events and level indications; its outputs are valve commands. **A1–A3** are its child functions. Arrows between children, such as *operating step* and *filling-step activity*, are internal to A0.

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control timed tank filling** | start; stop; LSH; LSHH | TON_Duration; TOF_Duration; initial-step rule; filling/pause transition rules; stop priority; LSH termination rule; LSHH avoidance requirement; discharge-valve inhibition | fill_valve; discharge_valve | OpenPLC Runtime; controller program; TON and TOF function blocks; Modbus TCP connection; Factory I/O tank, level switches, and valve interfaces |
| **A1** | **Manage the operating step** | start; stop; LSH; LSHH; ton_q; tof_q | Initial step 0; transition from step 0 to filling on start; transition from filling to pause on ton_q AND NOT LSH; transition from pause to filling on NOT tof_q; termination to step 0 on LSH during an active cycle; overriding return to step 0 on stop; LSHH avoidance requirement | Operating step; filling-step activity | OpenPLC Runtime; step-state memory; transition logic |
| **A2** | **Time the filling and pause intervals** | Filling-step activity | TON_Duration; TOF_Duration; TON on-delay semantics; TOF off-delay semantics; common timer input assignment to filling-step activity | ton_q; tof_q | OpenPLC TON function block; OpenPLC TOF function block; runtime time base |
| **A3** | **Generate the valve commands** | Operating step | Filling-step-only valve enable; no-output rule for step 0; fill-valve closure in pause; overriding output inhibition on stop; permanent discharge-valve inhibition | fill_valve; discharge_valve | OpenPLC output logic; output image; Modbus TCP output mapping; Factory I/O valve interfaces |

### Interpretation and interface notes

- **start** is the one-scan press event derived from `StartCommand` at `%IX100.0`, not a continuously held start level. **stop**, **LSH**, and **LSHH** correspond to `%IX100.1`, `%IX100.2`, and `%IX100.3`.
- **fill_valve** maps to `FillValve` at `%QX100.0`; **discharge_valve** maps to `DischargeValve` at `%QX100.1` and remains FALSE.
- A2 receives TRUE throughout the filling step and FALSE otherwise. Consequently, **ton_q** becomes TRUE after continuous filling for `TON_Duration`, while **tof_q** remains TRUE for `TOF_Duration` after filling is left.
- **LSHH is a safety constraint, not a specified transition trigger.** The task explicitly ends filling at LSH but does not prescribe an additional LSHH-triggered interlock. Such an interlock should not silently be added to the functional requirements. Whether closure at 2.4 m guarantees that 2.7 m is never reached depends on plant dynamics and response delays not supplied here.
