The model below treats the **PLC control application** as the system boundary, rather than the tank itself. Thus, command and level signals are inputs; valve commands are outputs; sequencing requirements and timer settings are controls; and the PLC runtime, timer function blocks, and I/O interface are mechanisms.

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control timed tank filling** | start; stop; LSH; LSHH | TON_Duration; TOF_Duration; initial-step requirement; filling/pause/resume rules; LSH completion rule; stop priority; LSHH non-reach requirement; discharge-valve prohibition | fill_valve; discharge_valve | OpenPLC Runtime; PLC control program; TON and TOF function blocks; Modbus TCP interface; Factory I/O tank, level switches, and valves |
| **A1** | **Manage filling sequence** | start; stop; LSH; LSHH; ton_q; tof_q | Initial step 0; start-triggered filling rule; transition to pause on ton_q AND NOT LSH; transition from pause to filling on NOT tof_q; return to step 0 on LSH; overriding return to step 0 on stop; LSHH non-reach requirement | Filling-step activity; sequence-state status | PLC sequence logic; state memory; OpenPLC scan execution |
| **A2** | **Time filling and pause intervals** | Filling-step activity | TON_Duration; TOF_Duration; TON on-delay semantics; TOF off-delay semantics; timer initialization requirements | ton_q; tof_q | TON function block; TOF function block; PLC time base; OpenPLC Runtime |
| **A3** | **Generate valve commands** | Filling-step activity; sequence-state status; stop | Fill-valve activation only during filling; no-output requirement in step 0; closed-fill-valve requirement during pause; overriding output suppression on stop; discharge_valve permanently FALSE | fill_valve; discharge_valve | PLC output logic; OpenPLC output image; Modbus TCP output mapping |

**Interpretation notes**

- **Internal arrows:** A1 supplies filling-step activity to A2 and A3. A2 returns `ton_q` and `tof_q` to A1. Both timers use filling-step activity as their `IN`.
- **Signal mapping:** `start` is the one-scan press event derived from StartCommand at `%IX100.0`; `stop`, `LSH`, and `LSHH` correspond to `%IX100.1`, `%IX100.2`, and `%IX100.3`. `fill_valve` and `discharge_valve` map to `%QX100.0` and `%QX100.1`.
- **Priority:** `stop` overrides normal sequencing. `LSH` ends filling rather than initiating a pause, even if `ton_q` is simultaneously TRUE.
- **LSHH limitation:** The task states that LSHH must never be reached, but does **not** prescribe an LSHH-triggered transition. It is therefore represented as an available safety-related input and a non-reach constraint, without inventing an additional trip sequence. Whether closing at LSH guarantees this constraint depends on the plant dynamics and response time.
