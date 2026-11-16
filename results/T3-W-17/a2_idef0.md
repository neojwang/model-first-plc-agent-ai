The model below treats the **PLC control application** as the system boundary. **A0** is the context function; **A1–A3** are its child functions. Plant signals are inputs, the task rules and timer parameters are controls, and the runtime and communication facilities are mechanisms.

Signal arrows use the required identifiers. In particular, `start` denotes the one-scan press event derived from `StartCommand`, not its continuously held value.

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control timed tank filling** | `start`; `stop`; `LSH`; `LSHH` | `TON_Duration`; `TOF_Duration`; initial-step rule; filling/pause transition rules; stop priority; upper-level safety constraint; discharge prohibition | `fill_valve`; `discharge_valve` | OpenPLC Runtime; PLC application; TON and TOF function blocks; Modbus TCP connection to Factory I/O |
| **A1** | **Coordinate filling-cycle steps** | `start`; `stop`; `LSH`; `LSHH`; `ton_q`; `tof_q` | **Initialization:** step 0 is active initially. **Stop priority:** `stop` returns the cycle to step 0 from any step. **Start:** `start` initiates the filling step from step 0, provided the filling target is not already detected. **Target completion:** `LSH` ends the filling cycle and returns it to step 0. **Timed pause:** in the filling step, `ton_q` with no `LSH` selects the pause step. **Resumption:** in the pause step, FALSE `tof_q` permits renewed filling if neither `stop` nor `LSH` requires step 0. **Safety:** the LSHH level must not be reached. | Step-0 activity; filling-step activity; pause-step activity | PLC step-sequencing logic; persistent step-state storage; cyclic PLC execution |
| **A2** | **Time filling and pause intervals** | Filling-step activity | `TON_Duration`; `TOF_Duration`; TON semantics with IN equal to filling-step activity; TOF semantics with IN equal to filling-step activity | `ton_q`; `tof_q` | TON function-block instance; TOF function-block instance; PLC time base and timer-instance storage |
| **A3** | **Generate valve commands** | Step-0 activity; filling-step activity; pause-step activity; `stop` | **Fill command rule:** `fill_valve` is TRUE only during the filling step and while `stop` is FALSE. **Inactive-step rule:** step 0 and the pause step command the fill valve closed. **Discharge prohibition:** `discharge_valve` remains FALSE. **Stop override:** `stop` forces both outputs FALSE. | `fill_valve`; `discharge_valve` | PLC output logic; output image; Modbus TCP output mapping |

**Internal arrow connections**

- A1 → A2: **filling-step activity**
- A2 → A1: **`ton_q`**, **`tof_q`**
- A1 → A3: **step-0 activity**, **filling-step activity**, **pause-step activity**

**Interpretation notes**

- `start`, `stop`, `LSH`, and `LSHH` correspond to the specified input tags at `%IX100.0`–`%IX100.3`; `fill_valve` and `discharge_valve` correspond to `%QX100.0` and `%QX100.1`.
- `LSH` is the normal completion indication at **2.4 m**. `LSHH` at **2.7 m** expresses the upper safety boundary. The task does **not** specify a separate LSHH-triggered transition, so the model does not silently invent one.
- “LSHH must never be reached” is a **safety constraint**, not something the timer logic alone proves. Its physical satisfaction depends on adequate margin between LSH detection and the maximum level reached after valve closure.
