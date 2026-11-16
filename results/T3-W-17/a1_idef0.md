## 1. Model scope and notation

The **A0 context function** is decomposed into four child functions, **A1–A4**. Function names are verb phrases; arrow names are noun phrases.

The model uses three steps:

- **Step 0 — Idle:** initial step; both valve outputs are FALSE.
- **Step 1 — Filling:** the fill valve is open.
- **Step 2 — Pause:** both valve outputs are FALSE.

**Control priority:** `stop` overrides all other conditions. Level termination overrides timer-based transitions.

`LSH` is the normal filling endpoint. As an additional protective action, `LSHH` also forces Step 0 and closes the valves. This does not replace the requirement to stop filling at `LSH`.

## 2. IDEF0 ICOM tables

### A0 — Context function

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| A0 | Control timed tank filling | **Operator command signals:** StartCommand, StopCommand; **Tank level signals:** `LSH`, `LSHH` | **Filling sequence rules**; **Initial-step rule**; **Stop-priority rule**; **Level-termination rules**; **Timer settings:** TON_Duration, TOF_Duration; **TON and TOF semantics**; **Discharge-inhibition rule**; **I/O mapping** | **Valve commands:** `fill_valve`, `discharge_valve` | OpenPLC Runtime; cyclic PLC task; edge-detection memory; sequence-state memory; TON and TOF function-block instances; Modbus TCP connection; Factory I/O digital tank, level switches, and valves |

### A0 decomposition

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| A1 | Acquire command and level signals | **Operator command signals:** StartCommand, StopCommand; **Tank level signals:** `LSH`, `LSHH`; **Previous StartCommand value** | **Input address mapping**; **Start-event definition**; **Input sampling rules** | **Start event:** `start`; **Stop status:** `stop`; **Level statuses:** `LSH`, `LSHH`; **Updated StartCommand value** | OpenPLC input process image; Modbus TCP connection; rising-edge detector and memory |
| A2 | Evaluate filling and pause timing | **Filling-step activity** | **Timer settings:** TON_Duration, TOF_Duration; **TON semantics**; **TOF semantics**; **Timer initialization rules** | **On-delay completion status:** `ton_q`; **Off-delay output status:** `tof_q` | TON function-block instance; TOF function-block instance; PLC time base; cyclic PLC task |
| A3 | Select the active sequence step | **Start event:** `start`; **Stop status:** `stop`; **Level statuses:** `LSH`, `LSHH`; **Timer statuses:** `ton_q`, `tof_q`; **Current step status** | **Initial-step rule**; **Step-transition rules**; **Stop-priority rule**; **Level-termination rules**; **Single-active-step rule** | **Selected step status**; **Filling-step activity** | Sequence-state memory; PLC execution logic |
| A4 | Apply valve commands | **Selected step status**; **Stop status:** `stop`; **Level statuses:** `LSH`, `LSHH` | **Valve actuation rules**; **Stop-priority rule**; **Level-closure rules**; **Discharge-inhibition rule**; **Output address mapping** | **Fill command:** `fill_valve`; **Discharge command:** `discharge_valve` | OpenPLC output process image; Modbus TCP connection; Factory I/O valve interfaces |

The **Selected step status** from A3 becomes the **Current step status** for subsequent sequence evaluation. The **Updated StartCommand value** from A1 becomes its **Previous StartCommand value** at the next input evaluation.

## 3. Internal arrow connections

| Arrow noun phrase | Source | Destination |
|---|---|---|
| Start event: `start` | A1 | A3 input |
| Stop status: `stop` | A1 | A3 and A4 inputs |
| Level statuses: `LSH`, `LSHH` | A1 | A3 and A4 inputs |
| Filling-step activity | A3 | A2 input |
| On-delay completion status: `ton_q` | A2 | A3 input |
| Off-delay output status: `tof_q` | A2 | A3 input |
| Selected step status | A3 | A4 input; sequence-state feedback |
| Updated StartCommand value | A1 | Start-event memory feedback |
| Fill command: `fill_valve` | A4 | A0 output boundary |
| Discharge command: `discharge_valve` | A4 | A0 output boundary |

## 4. Behavioral controls attached to the model

These tables define the controls used by A2–A4; they are not program code.

### Input interpretation and mapping

| Model identifier | Physical tag/address | Meaning |
|---|---|---|
| `start` | StartCommand, `%IX100.0` | Rising-edge event, TRUE only for the scan in which the press is detected |
| `stop` | StopCommand, `%IX100.1` | Stop-button level |
| `LSH` | LSH, `%IX100.2` | High-level detection at 2.4 m |
| `LSHH` | LSHH, `%IX100.3` | High-high-level detection at 2.7 m |
| `ton_q` | Internal TON output Q | Filling-duration completion status |
| `tof_q` | Internal TOF output Q | Filling activity with an off-delay |
| `fill_valve` | FillValve, `%QX100.0` | Fill-valve command |
| `discharge_valve` | DischargeValve, `%QX100.1` | Discharge-valve command; always FALSE |

### Timer rules

| Timer | Input condition | Preset | Output behavior |
|---|---|---|---|
| TON | Filling-step activity | TON_Duration | `ton_q` becomes TRUE after continuous filling activity for the preset duration; leaving Filling resets the TON |
| TOF | Filling-step activity | TOF_Duration | `tof_q` is TRUE during Filling and remains TRUE for the preset duration after Filling is left |

Both timers are evaluated cyclically, including during Idle and Pause. A stop closes the valves immediately through sequence/output control; it does **not** require the TOF’s internal off-delay to finish.

### Step-transition rules

Apply the first applicable rule in priority order.

| Priority | Current step | Receptivity | Selected step |
|---|---|---|---|
| 1 | Any | `stop` | Step 0 — Idle |
| 2 | Any | `LSH OR LSHH` | Step 0 — Idle |
| 3 | Step 0 — Idle | `start AND NOT stop AND NOT LSH AND NOT LSHH` | Step 1 — Filling |
| 4 | Step 1 — Filling | `ton_q AND NOT LSH AND NOT LSHH` | Step 2 — Pause |
| 5 | Step 2 — Pause | `NOT tof_q AND NOT LSH AND NOT LSHH` | Step 1 — Filling |
| 6 | Any | No applicable transition | Current step |

A `start` event during Filling or Pause has no effect. After stopping or reaching `LSH`, a new press is required to start another cycle.

### Valve actuation rules

| Condition | `fill_valve` | `discharge_valve` |
|---|---|---|
| Step 1 — Filling, with `stop`, `LSH`, and `LSHH` all FALSE | TRUE | FALSE |
| Step 0 — Idle or Step 2 — Pause | FALSE | FALSE |
| `stop OR LSH OR LSHH` | FALSE | FALSE |

## 5. Safety boundary

The intended sequence closes the fill valve at **LSH = 2.4 m**, before **LSHH = 2.7 m**. Closing on `LSHH` is only a protective fallback: if `LSHH` becomes TRUE, the “must never be reached” requirement has already been violated.

Physical assurance therefore also depends on correct level sensing, valve closure, communication latency, PLC scan time, and residual inflow. The model assumes these allow filling to stop within the 0.3 m margin.
