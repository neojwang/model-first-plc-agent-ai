## A0 context and decomposition

**A0 — Control timed tank filling**

The model boundary includes input acquisition, start-event detection, timer evaluation, step sequencing, and output-command generation. Tank dynamics and liquid flow remain outside the boundary.

All arrow labels below are noun phrases; all function names are verb phrases. The identifiers `start`, `stop`, `LSH`, `LSHH`, `ton_q`, `tof_q`, `fill_valve`, and `discharge_valve` retain their specified meanings.

### ICOM table

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control timed tank filling** | Command and level signal image | Initial-step specification; Start-event definition; Sequence and priority rules; TON_Duration; TOF_Duration; Level-switch configuration; I/O mapping; Discharge prohibition | `fill_valve`; `discharge_valve` | OpenPLC Runtime; PLC scan cycle; Modbus TCP connection; Factory I/O driver; TON and TOF instances; State and edge memory |
| **A1** | **Acquire commands and level indications** | Command and level signal image | I/O mapping; Start-event definition; Input sampling rules | `start`; `stop`; `LSH`; `LSHH` | OpenPLC input image; Modbus TCP connection; Factory I/O driver; Start-edge memory |
| **A2** | **Evaluate filling timers** | Filling-step activity | TON_Duration; TOF_Duration; TON semantics; TOF semantics; Timer initialization rules | `ton_q`; `tof_q` | TON instance; TOF instance; PLC time base |
| **A3** | **Select the operating step** | `start`; `stop`; `LSH`; `LSHH`; `ton_q`; `tof_q` | Initial-step specification; Sequence and priority rules; Level-switch configuration | Step-state record; Filling-step activity | Step-state memory; PLC scan cycle |
| **A4** | **Generate valve commands** | Step-state record; `stop`; `LSH`; `LSHH` | Output authorization rules; Discharge prohibition; I/O mapping | `fill_valve`; `discharge_valve` | OpenPLC output image; Modbus TCP connection; Factory I/O driver |

### Parent–child arrow balance

The external arrows of A0 are distributed among its children as follows:

- **Command and level signal image:** A0 input → A1 input.
- **Controls:** A0 controls → the applicable child controls listed above.
- **`fill_valve`, `discharge_valve`:** A4 outputs → A0 outputs.
- **Mechanisms:** A0 mechanisms → the applicable child mechanisms.

Internal child connections are:

| Arrow | Source | Destination |
|---|---|---|
| `start` | A1 | A3 |
| `stop` | A1 | A3, A4 |
| `LSH` | A1 | A3, A4 |
| `LSHH` | A1 | A3, A4 |
| Filling-step activity | A3 | A2 |
| `ton_q` | A2 | A3 |
| `tof_q` | A2 | A3 |
| Step-state record | A3 | A4 |

The A3 → A2 → A3 feedback represents cyclic PLC execution and timer state, not an instantaneous combinational loop.

## I/O and vocabulary binding

“Command and level signal image” groups the four physical input signals at the A0 boundary.

| Physical tag or parameter | Address | Model meaning |
|---|---|---|
| StartCommand | `%IX100.0` | Source of `start`; a rising-edge event lasting one scan |
| StopCommand | `%IX100.1` | `stop`; a level-sensitive command |
| LSH | `%IX100.2` | `LSH`; liquid detection at 2.4 m |
| LSHH | `%IX100.3` | `LSHH`; high-high detection at 2.7 m |
| FillValve | `%QX100.0` | Destination of `fill_valve` |
| DischargeValve | `%QX100.1` | Destination of `discharge_valve` |
| TON_Duration | Parameter | Filling-phase duration limit |
| TOF_Duration | Parameter | Pause duration after departure from the filling step |

OpenPLC exchanges these signals with Factory I/O through the configured Modbus TCP connection, with Factory I/O acting as the slave device.

## Behavioral controls

These rules define the controls referenced in the ICOM table; they are not additional IDEF0 functions.

### Step definitions

| Step | Meaning | Output authorization |
|---|---|---|
| **Step 0 — Initial/idle** | Initial state and destination after completion or stop | Neither output is authorized |
| **Step 1 — Filling** | Active filling phase | `fill_valve` is authorized, subject to the output interlocks |
| **Step 2 — Pause** | Timed interruption of filling | Neither output is authorized |

### Sequence and priority rules

Apply the following rules in priority order:

1. **Stop priority:** whenever `stop` is TRUE, select step 0 and force both outputs FALSE.
2. **Level priority:** whenever `LSH` or `LSHH` is TRUE, select step 0 and keep both outputs FALSE.
3. **Start:** from step 0, `start` permits entry to step 1 only while `stop`, `LSH`, and `LSHH` are all FALSE.
4. **Filling timeout:** from step 1, `ton_q` TRUE with `LSH` FALSE causes entry to step 2, provided neither higher-priority rule applies.
5. **Pause completion:** from step 2, `tof_q` FALSE causes entry to step 1, provided neither higher-priority rule applies.
6. **State retention:** otherwise retain the current step.

A held StartCommand therefore does not restart filling after completion or stop release; a new `start` event is required.

### Timer rules

- Both timers receive **Filling-step activity** as their input condition.
- TON times while step 1 is active. Its output `ton_q` becomes TRUE after TON_Duration and resets when step 1 is inactive.
- TOF has `tof_q` TRUE while step 1 is active. After departure from step 1, it remains TRUE for TOF_Duration, then becomes FALSE.
- Timer instances are evaluated every scan, including during step 0 and step 2.
- Stop forces the step and outputs to their safe conditions; it does **not** depend on `tof_q` becoming FALSE. TOF may finish its off-delay while the controller remains idle.

### Output authorization rules

- `fill_valve` is TRUE only in step 1 while `stop`, `LSH`, and `LSHH` are all FALSE.
- `discharge_valve` is always FALSE.
- Initial output values are FALSE.

## High-high-level qualification

The required normal completion point is **LSH at 2.4 m**. This model additionally treats `LSHH` as a defensive fill-inhibit and return-to-idle condition.

However, an `LSHH` interlock acts only once that level is detected; it cannot itself guarantee that 2.7 m is never reached. That physical requirement also depends on adequate margin between LSH and LSHH, sensor correctness, scan and communication latency, valve closure time, and residual inflow. These plant assumptions must be validated before accepting the control design.
