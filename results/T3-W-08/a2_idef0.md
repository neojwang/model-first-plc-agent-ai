The model below treats the **PLC-based filling controller** as the system boundary. Arrow names are noun phrases or the exact identifiers specified in the task. Internal arrows connect the child functions; for example, **Operating-step status** feeds both timer execution and output determination.

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control timed tank filling** | `start`; `stop`; `LSH`; `LSHH` | Initial-step rule; filling-and-pause sequence rules; `TON_Duration`; `TOF_Duration`; stop-priority rule; high-level completion rule; high-high level avoidance requirement; discharge-valve prohibition | `fill_valve`; `discharge_valve` | OpenPLC Runtime; PLC application; TON and TOF function blocks; Modbus TCP connection; Factory I/O tank and I/O interfaces |
| **A1** | **Select the operating step** | `start`; `stop`; `LSH`; `LSHH`; `ton_q`; `tof_q`; Operating-step status | Initial-step rule; transition rules; stop-priority rule; high-level completion rule; high-high level avoidance requirement | Operating-step status | OpenPLC Runtime; step-state memory; sequence-selection logic |
| **A2** | **Time the filling and pause phases** | Operating-step status | `TON_Duration`; `TOF_Duration`; timer execution rules: TON.IN and TOF.IN equal filling-step activity | `ton_q`; `tof_q` | OpenPLC Runtime; TON function block and instance memory; TOF function block and instance memory |
| **A3** | **Determine and transmit valve commands** | Operating-step status; `stop` | Filling-step output rule; initial-step and pause-step output rules; stop-priority rule; discharge-valve prohibition; output-address mapping | `fill_valve`; `discharge_valve` | OpenPLC output image; Modbus TCP connection; Factory I/O driver; fill-valve and discharge-valve interfaces |

### Meaning of the principal controls

- **Operating-step status** identifies one of three steps: **step 0**, **filling**, or **pause**.
- **Transition rules** are:
  - Step 0 → filling on `start`.
  - Filling → step 0 on `LSH`.
  - Filling → pause on `ton_q AND NOT LSH`.
  - Pause → filling on `NOT tof_q`, provided `LSH` has not completed the cycle.
  - Pause → step 0 on `LSH`.
  - Any step → step 0 whenever `stop` is TRUE.
- **Timer execution rules:** both timers receive filling-step activity as their IN value. TON limits each filling phase; TOF holds `tof_q` TRUE for `TOF_Duration` after filling is left.
- **Output rules:** `fill_valve` is TRUE only in the filling step and only when `stop` is FALSE. `discharge_valve` is always FALSE.
- **Interface mapping:** `start` is the one-scan press event derived from StartCommand at `%IX100.0`; `stop`, `LSH`, and `LSHH` correspond to `%IX100.1`, `%IX100.2`, and `%IX100.3`. `fill_valve` and `discharge_valve` map to `%QX100.0` and `%QX100.1`.

**Safety qualification:** The task specifies that LSHH must never be reached, but does not specify an LSHH-triggered transition or alarm. Accordingly, the model retains `LSHH` as safety-condition information without inventing an additional trip sequence. Whether stopping filling at LSH actually prevents reaching LSHH also depends on plant dynamics and control/communication delays; it cannot be established from the stated sequence alone.
