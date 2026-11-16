The model below treats the function being modeled as the **PLC control of tank filling**, rather than the physical movement of liquid. Signal names follow the required vocabulary; internal arrows use noun phrases.

In IDEF0 notation, the context diagram is **A-0**, containing function **A0**. Its decomposition contains functions **A1–A4**.

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control timed tank filling** | `start`; `stop`; `LSH`; `LSHH` | `TON_Duration`; `TOF_Duration`; initial-step rule; filling-and-pause sequence rules; stop-priority rule; level-completion rule; LSHH nonreachability constraint; discharge-valve closure requirement | `fill_valve`; `discharge_valve` | OpenPLC Runtime; PLC sequence logic; TON and TOF timer instances; Modbus TCP connection; Factory I/O interface |
| **A1** | **Select the operating step** | `start`; `stop`; `LSH`; `LSHH`; `ton_q`; `tof_q` | Initial-step rule; stop-priority rule; level-completion rule; step-transition rules; LSHH nonreachability constraint | Operating-step state; filling-step activity | OpenPLC Runtime; step-state memory; sequence logic |
| **A2** | **Time the filling phase** | Filling-step activity | `TON_Duration`; TON operating rules | `ton_q` | OpenPLC Runtime; TON timer instance |
| **A3** | **Time the filling pause** | Filling-step activity | `TOF_Duration`; TOF operating rules | `tof_q` | OpenPLC Runtime; TOF timer instance |
| **A4** | **Generate valve commands** | Filling-step activity | `stop`; initial-step output rule; pause-step output rule; discharge-valve closure requirement | `fill_valve`; `discharge_valve` | OpenPLC Runtime; output-assignment logic; Modbus TCP output mapping |

### Meaning of the sequence controls

- **Initial-step rule:** Step 0 is the initial state and commands both outputs FALSE.
- **Stop-priority rule:** `stop` overrides all other conditions, returns the sequence to step 0, and forces both outputs FALSE.
- **Level-completion rule:** `LSH` ends an active filling cycle, including a paused cycle, and returns the sequence to step 0 with the fill valve closed.
- **Step-transition rules:**
  - Step 0 → filling on `start`, provided neither `stop` nor `LSH` requires the idle state.
  - Filling → pause when `ton_q` is TRUE and `LSH` is FALSE.
  - Pause → filling when `tof_q` is FALSE, unless overridden by `stop` or `LSH`.
- **Timer behavior:** Both timers receive filling-step activity as their `IN`. TON therefore limits each filling phase; TOF holds `tof_q` TRUE for `TOF_Duration` after filling ends.
- **Valve behavior:** `fill_valve` is TRUE only during the filling step and while `stop` is FALSE. `discharge_valve` is always FALSE.

**Interface and safety qualifications**

- `start` is the specified one-scan press event, not the continuously held button level.
- `LSHH` is retained as a level-status input associated with the **nonreachability constraint**. The task does not specify an additional transition triggered by `LSHH`; inventing one would add behavior. Preventing the level from reaching 2.7 m depends on stopping at `LSH` at 2.4 m with adequate allowance for scan, communication, and valve-closing delays.
