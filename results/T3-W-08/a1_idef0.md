## A0 — Control timed tank filling

The model uses **A0 as the context function**, as requested, and decomposes it into A1–A4. Inputs enter a function, controls constrain its execution, outputs leave it, and mechanisms perform it.

**Operating interpretation**
- `start` is a one-scan rising-edge event derived from StartCommand, not its maintained level.
- Step 0 is idle; Step 1 is filling; Step 2 is the pause.
- `stop` overrides every other condition. Level detection overrides timer-based progression.
- `discharge_valve` remains FALSE in every step.
- As a conservative protective addition, `LSHH` inhibits filling and forces Step 0. This does **not** make reaching LSHH acceptable: normal filling must terminate at LSH.

### IDEF0 ICOM table

Every function name is a verb phrase. Arrow names are noun phrases or the required signal identifiers.

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control timed tank filling** | StartCommand signal; StopCommand signal; LSH signal; LSHH signal | Initial-step rule; Start-event rule; Stop-priority rule; Level-termination rule; High-high protection rule; Timed-cycle rules; TON_Duration; TOF_Duration; Discharge-inhibition rule; I/O mapping specification | `fill_valve`; `discharge_valve` | OpenPLC Runtime; Factory I/O tank scene; Modbus TCP connection; PLC state memory; IEC TON and TOF timer instances |
| **A1** | **Acquire commands and level indications** | StartCommand signal; StopCommand signal; LSH signal; LSHH signal | I/O mapping specification; Start-event rule | `start`; `stop`; `LSH`; `LSHH` | OpenPLC input image; Modbus TCP connection; Rising-edge detector; Previous-command memory |
| **A2** | **Evaluate filling and pause timing** | Filling-step activity | TON_Duration; TOF_Duration; Timed-cycle rules | `ton_q`; `tof_q` | IEC TON instance; IEC TOF instance; PLC time base; Timer-state memory |
| **A3** | **Select the active sequence step** | `start`; `stop`; `LSH`; `LSHH`; `ton_q`; `tof_q` | Initial-step rule; Stop-priority rule; Level-termination rule; High-high protection rule; Timed-cycle rules | Active-step selection; Filling-step activity | Sequence evaluator; Step-state memory; OpenPLC Runtime |
| **A4** | **Drive the valve outputs** | Active-step selection | `stop`; `LSH`; `LSHH`; Discharge-inhibition rule; I/O mapping specification | `fill_valve`; `discharge_valve` | OpenPLC output image; Modbus TCP connection; Factory I/O valve actuators |

### Internal arrow connections

These connections define the child diagram and its feedback paths.

| Arrow | Source | Destination |
|---|---|---|
| `start` | A1 | A3 input |
| `stop` | A1 | A3 input; A4 control |
| `LSH` | A1 | A3 input; A4 control |
| `LSHH` | A1 | A3 input; A4 control |
| Filling-step activity | A3 | A2 input |
| `ton_q` | A2 | A3 input |
| `tof_q` | A2 | A3 input |
| Active-step selection | A3 | A4 input |
| `fill_valve` | A4 | A0 boundary output |
| `discharge_valve` | A4 | A0 boundary output |

The A0 boundary inputs and controls are distributed to the children shown in the ICOM table; no additional external input or output is introduced.

## Behavioral definitions of the controls

### Sequence selection

Conditions are evaluated in the priority order shown. The identifiers in the receptivities use the required vocabulary.

| Priority | Current step | Receptivity | Next step |
|---|---|---|---|
| 1 | Any | `stop` | Step 0 |
| 2 | Any | `LSHH` | Step 0 |
| 3 | Any | `LSH` | Step 0 |
| 4 | Step 0 | `start AND NOT stop AND NOT LSH AND NOT LSHH` | Step 1 |
| 4 | Step 1 | `ton_q AND NOT LSH` | Step 2 |
| 4 | Step 2 | `NOT tof_q` | Step 1 |

Otherwise, retain the current step. A `start` event during filling or pause is ignored. A new button press is required after a stop or completed fill.

### Timer behavior

- **Filling-step activity** is TRUE only in Step 1.
- TON receives this activity as its IN and TON_Duration as its preset. Its Q is `ton_q`; leaving Step 1 resets TON.
- TOF receives the same activity as its IN and TOF_Duration as its preset. Its Q is `tof_q`.
- During Step 1, `tof_q` is TRUE. After Step 1 is left, it remains TRUE for TOF_Duration.
- Step 2 ends when `tof_q` becomes FALSE.
- Neither timer output can initiate filling from Step 0.

### Output behavior

- `fill_valve` is TRUE only in Step 1, with `stop`, `LSH`, and `LSHH` all FALSE.
- `discharge_valve` is always FALSE.
- Step 0 and Step 2 command both outputs FALSE.

## Boundary I/O mapping

| Scene / runtime tag | Address | Model signal |
|---|---|---|
| StartCommand | `%IX100.0` | Source of `start` |
| StopCommand | `%IX100.1` | `stop` |
| LSH, 2.4 m | `%IX100.2` | `LSH` |
| LSHH, 2.7 m | `%IX100.3` | `LSHH` |
| FillValve | `%QX100.0` | `fill_valve` |
| DischargeValve | `%QX100.1` | `discharge_valve` |

**Physical constraint:** “LSHH must never be reached” depends on the 0.3 m margin above LSH being sufficient for sensing, communication, scan, valve-closing, and residual-flow delays. The LSHH interlock is a protective fallback, not proof that this physical constraint is satisfied.
