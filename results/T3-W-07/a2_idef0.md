### IDEF0 functional model

The context function is **A0 — Control timed tank filling**. Its children are **A1–A4** below. These are functions, not sequential steps; the initial, filling, and pause steps are represented by the internal **operating state**.

Signal information is treated as **input data** because the controller evaluates it to determine state and outputs. Timing parameters, transition rules, and safety requirements are **controls**. Internal arrows connect child functions and do not appear at the A0 boundary.

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control timed tank filling** | start; stop; LSH; LSHH | TON_Duration; TOF_Duration; initial-state requirement; filling/pause transition rules; stop-priority requirement; high-level completion requirement; high-high-level avoidance requirement; discharge-valve inhibition requirement | fill_valve; discharge_valve | OpenPLC Runtime; PLC application; Factory I/O tank scene; Modbus TCP connection; command interface; level switches; valve actuators |
| **A1** | **Determine operating state** | start; stop; LSH; LSHH; ton_q; tof_q; stored operating state | Initial-state requirement; stop-priority requirement; high-level completion requirement; filling/pause transition rules; high-high-level avoidance requirement | Operating state; filling-step activity; stored operating state | PLC state-transition logic; state memory; OpenPLC cyclic execution |
| **A2** | **Time filling activity** | Filling-step activity | TON_Duration; TON behavior specification | ton_q | TON function-block instance; OpenPLC time base |
| **A3** | **Time filling interruption** | Filling-step activity | TOF_Duration; TOF behavior specification | tof_q | TOF function-block instance; OpenPLC time base |
| **A4** | **Generate valve commands** | Operating state; stop | Filling-step output rule; initial-step and pause-step output rules; stop-priority requirement; discharge-valve inhibition requirement | fill_valve; discharge_valve | PLC output logic; OpenPLC output image; Modbus TCP output mapping |

### Meaning of the principal controls

- **Initial-state requirement:** Initialize the operating state to step 0, with both outputs FALSE.
- **Stop-priority requirement:** Whenever `stop` is TRUE, select step 0 and force both outputs FALSE, overriding other transitions.
- **High-level completion requirement:** During an active filling cycle, `LSH` ends the cycle and returns the operating state to step 0. This takes precedence over entering or leaving the pause state.
- **Filling/pause transition rules:**
  - Step 0 → filling on `start`, provided `stop` is FALSE and `LSH` is not already detected.
  - Filling → pause when `ton_q` is TRUE and `LSH` is FALSE.
  - Pause → filling when `tof_q` is FALSE, provided neither stop nor high-level completion applies.
- **Timer behavior:** Both timers receive **filling-step activity** as their IN value. TON measures continuous filling activity; TOF remains TRUE for `TOF_Duration` after that activity becomes FALSE.
- **Output rules:** `fill_valve` is TRUE only in the filling state and while `stop` is FALSE. `discharge_valve` is always FALSE.

### Boundary and safety qualifications

- `start` is the specified one-scan press event, not the sustained value of StartCommand. Its derivation belongs to the command interface at this model boundary. `stop`, `LSH`, and `LSHH` retain their specified meanings. The output arrows `fill_valve` and `discharge_valve` map to the stated physical output addresses.
- **LSHH avoidance is a constraint, not a specified transition.** The task does not define a separate response to `LSHH`; therefore, this model does not silently add a high-high trip. Closing at `LSH` is the specified means of avoiding `LSHH`. Whether the liquid can *never* reach 2.7 m also depends on plant dynamics, sensing, scan/communication delays, and valve closure behavior; the supplied requirements alone do not establish that physical guarantee.
