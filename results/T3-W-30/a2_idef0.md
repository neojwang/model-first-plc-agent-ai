The model below treats the **PLC control application** as the system boundary, rather than the physical tank. A0 is the context function; A1–A4 are its child functions. Arrows passed between child functions are internal to A0.

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control timed tank filling** | `start`; `stop`; `LSH`; `LSHH` | `TON_Duration`; `TOF_Duration`; initial-step rule; filling and pause sequence rules; stop-priority rule; upper-level termination rule; `LSHH` non-reachability requirement; discharge prohibition | `fill_valve`; `discharge_valve` | OpenPLC Runtime; PLC control program; TON and TOF timer instances; Modbus TCP connection to Factory I/O |
| **A1** | **Select the operating step** | `start`; `stop`; `LSH`; `LSHH`; `ton_q`; `tof_q` | Initial state = step 0; `stop` priority; step 0 → filling on `start`; filling → step 0 on `LSH`; filling → pause on `ton_q` AND NOT `LSH`; pause → filling on NOT `tof_q`; `LSHH` non-reachability requirement | Operating step; filling-step activity | PLC sequence logic; operating-step memory; OpenPLC Runtime |
| **A2** | **Time each filling phase** | Filling-step activity | `TON_Duration`; TON semantics: IN equals filling-step activity; elapsed-time reset when IN is FALSE | `ton_q` | TON timer instance; PLC time base; OpenPLC Runtime |
| **A3** | **Time each filling pause** | Filling-step activity | `TOF_Duration`; TOF semantics: IN equals filling-step activity; Q remains TRUE for the preset interval after IN becomes FALSE | `tof_q` | TOF timer instance; PLC time base; OpenPLC Runtime |
| **A4** | **Generate valve commands** | Operating step; `stop` | `fill_valve` TRUE only in the filling step; no active outputs in step 0 or pause; all outputs FALSE whenever `stop` is TRUE; `discharge_valve` always FALSE | `fill_valve`; `discharge_valve` | PLC output logic; OpenPLC output image; Modbus TCP output mapping |

**Interpretation and implementation boundaries**

- **Identifier mapping:** `start` is the one-scan rising-edge event derived from `StartCommand` at `%IX100.0`; `stop` corresponds to `StopCommand` at `%IX100.1`. `LSH` and `LSHH` correspond to `%IX100.2` and `%IX100.3`. `fill_valve` and `discharge_valve` map to `%QX100.0` and `%QX100.1`.
- **Priority:** `stop` forces step 0 from every step. `LSH` terminates an active filling cycle, including its pause, so a detected upper level cannot lead to resumed filling.
- **Timer coupling:** Both timers receive **filling-step activity**, not the valve output or pause-step activity. Leaving the filling step resets TON and starts TOF’s off-delay.
- **Safety limitation:** “`LSHH` must never be reached” is a control constraint, not a specified additional transition. The task does not define an `LSHH` trip action. Preventing that level physically also depends on sensor response, scan/communication delays, valve closure, and residual inflow; the functional model alone cannot establish that guarantee.
