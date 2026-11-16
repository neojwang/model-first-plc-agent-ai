The model below treats the **PLC control function** as the system boundary. Thus, command and sensor signals are inputs, valve commands are outputs, operating rules and timer settings are controls, and the PLC and its software services are mechanisms.

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control timed tank filling** | start; stop; LSH; LSHH | TON_Duration; TOF_Duration; initial-step requirement; filling/pause sequencing rules; stop priority; LSH termination requirement; LSHH exclusion requirement; discharge-valve closure requirement | fill_valve; discharge_valve | OpenPLC Runtime; PLC control program; TON and TOF function blocks; Modbus TCP interface to Factory I/O |
| **A1** | **Determine the operating step** | start; stop; LSH; LSHH; ton_q; tof_q | Initial step 0; unconditional return to step 0 on stop; return to step 0 on LSH; start-triggered filling; pause condition `ton_q AND NOT LSH`; resumption condition `NOT tof_q`; LSHH exclusion requirement | Operating-step state; filling-step activity | PLC step-sequencing logic; state memory; cyclic execution |
| **A2** | **Time the filling and pause phases** | Filling-step activity | TON_Duration; TOF_Duration; TON on-delay semantics; TOF off-delay semantics; timer-input assignment requirement | ton_q; tof_q | TON function block; TOF function block; PLC time base |
| **A3** | **Generate valve commands** | Operating-step state; stop; LSH | Fill-valve activation rule; initial-step and pause-step closure rules; stop override; LSH termination requirement; permanent discharge-valve closure requirement | fill_valve; discharge_valve | PLC output-assignment logic; digital output image; Modbus TCP output mapping |

### Interpretation of the decomposition

- **A1 — Step sequencing**
  - Initial state: **step 0**.
  - In step 0, `start` initiates filling, provided `stop` and `LSH` are FALSE.
  - In the filling step, `ton_q AND NOT LSH` initiates the pause step.
  - In the pause step, `NOT tof_q` resumes filling.
  - `stop` returns the sequence to step 0 from any step.
  - `LSH` ends the active filling cycle and returns the sequence to step 0.

- **A2 — Timing**
  - Both timers receive **filling-step activity** as their `IN`.
  - TON produces `ton_q` after continuous filling for TON_Duration.
  - TOF keeps `tof_q` TRUE for TOF_Duration after the filling step is left.

- **A3 — Outputs**
  - `fill_valve` is TRUE only during the filling step, with `stop` and `LSH` FALSE.
  - `discharge_valve` is always FALSE.
  - Step 0 and the pause step command both outputs FALSE.

**Internal arrows:** A1 supplies operating-step state to A3 and filling-step activity to A2; A2 returns `ton_q` and `tof_q` to A1. These feedback connections are valid in an IDEF0 functional decomposition.

**Specification boundary:** `LSHH` is an available input, while “LSHH must never be reached” is a safety constraint. The task does not specify an additional transition triggered by `LSHH`; none is invented here. Whether closure at LSH prevents the level from reaching LSHH also depends on plant dynamics, scan time, and valve response.
