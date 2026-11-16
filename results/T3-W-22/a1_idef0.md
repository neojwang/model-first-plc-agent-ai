## A0 — Control timed tank filling

The model uses three internal steps:

- **Step 0 — Idle:** initial step; no output is driven.
- **Filling step:** the fill valve is open, subject to stop and level interlocks.
- **Pause step:** the fill valve is closed while the off-delay interval finishes.

The child functions A1–A4 execute as cooperating functions, not as a sequential flowchart. In particular, step activity feeds the timers, and timer results feed step selection.

### IDEF0 ICOM model

Every function name is a verb phrase. Arrow labels are noun phrases or the required signal identifiers.

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control timed tank filling** | `StartCommand`; `StopCommand`; `LSH`; `LSHH` | `TON_Duration`; `TOF_Duration`; Initial-step rule; Start-event rule; Stop-priority rule; Level-termination rule; Discharge-inhibition rule; I/O address map | `fill_valve`; `discharge_valve` | OpenPLC Runtime; PLC scan cycle; TON function block; TOF function block; Modbus TCP connection; Factory I/O tank and digital I/O |
| **A1** | **Acquire command events and level indications** | `StartCommand`; `StopCommand`; `LSH`; `LSHH` | Start-event rule; Input address map; Input-initialization policy | `start`; `stop`; `LSH`; `LSHH` | OpenPLC input image; Rising-edge detector; Previous-command memory; Modbus TCP connection |
| **A2** | **Select the operating step** | `start`; `ton_q`; `tof_q` | `stop`; `LSH`; `LSHH`; Initial-step rule; Transition rules; Stop-priority rule; Level-termination rule | Idle-step activity; Filling-step activity; Pause-step activity | Step-state memory; PLC scan cycle |
| **A3** | **Time the filling and pause intervals** | Filling-step activity | `TON_Duration`; `TOF_Duration`; Timer-behavior rules; Timer-initialization policy | `ton_q`; `tof_q` | TON function block instance; TOF function block instance; PLC time base |
| **A4** | **Interlock and drive the valve outputs** | Filling-step activity | `stop`; `LSH`; `LSHH`; Output-interlock rules; Discharge-inhibition rule; Output address map | `fill_valve`; `discharge_valve` | OpenPLC output image; Modbus TCP connection; Factory I/O valve actuators |

**Boundary convention:** `StartCommand` and `StopCommand` are raw mapped signals. The receptivities used by the control model are exactly `start`, `stop`, `LSH`, `LSHH`, `ton_q`, and `tof_q`. A1 passes the level signals through under their existing names.

## Arrow definitions and connections

| Arrow | Source → destination | Meaning |
|---|---|---|
| `StartCommand` | Plant interface → A1 | Raw start-button state |
| `StopCommand` | Plant interface → A1 | Raw stop-button state |
| `start` | A1 → A2 | One-scan event on a rising edge of `StartCommand` |
| `stop` | A1 → A2, A4 | Current stop-button state |
| `LSH` | A1 → A2, A4 | Liquid detection at 2.4 m |
| `LSHH` | A1 → A2, A4 | High-high liquid detection at 2.7 m |
| Idle-step activity | A2 → internal step-state boundary | Active status of step 0 |
| Filling-step activity | A2 → A3, A4 | Active status of the filling step |
| Pause-step activity | A2 → internal step-state boundary | Active status of the pause step |
| `ton_q` | A3 → A2 | TON completion status |
| `tof_q` | A3 → A2 | TOF output status |
| `fill_valve` | A4 → plant interface | Fill-valve command |
| `discharge_valve` | A4 → plant interface | Discharge-valve command, always FALSE |

Idle-step activity and Pause-step activity are internal state results; they do not cross the A0 boundary.

## Controls governing the child functions

### A1 — Start-event rule

- `start` is TRUE for only the scan in which a new press of `StartCommand` is detected.
- Holding `StartCommand` TRUE does not repeatedly start filling.
- `stop` follows `StopCommand`.
- Startup treatment of an already-held start button must be defined. A conservative policy is to require release and a subsequent press before producing `start`.

### A2 — Transition rules

The following priority applies: **stop override, level termination, then normal step transitions**.

| Current step | Receptivity or condition | Resulting step |
|---|---|---|
| Any step | `stop` | Step 0 |
| Filling or Pause | `LSH` or `LSHH` | Step 0 |
| Step 0 | `start` and NOT `stop` and NOT `LSH` and NOT `LSHH` | Filling |
| Filling | `ton_q` and NOT `LSH`, with no higher-priority condition | Pause |
| Pause | NOT `tof_q`, with no higher-priority condition | Filling |
| Any step | No applicable transition | Current step |

Thus, reaching `LSH` terminates the entire filling sequence, including during a pause. A subsequent filling sequence requires a new `start` event and clear level permissives.

### A3 — Timer-behavior rules

- Both timers use **Filling-step activity** as their input.
- **TON:** `ton_q` becomes TRUE after continuous filling activity for `TON_Duration`. Leaving Filling resets TON.
- **TOF:** `tof_q` is TRUE during Filling and remains TRUE for `TOF_Duration` after Filling is left.
- The Pause step ends when `tof_q` becomes FALSE.
- TOF may remain TRUE temporarily after a stop or level termination. It must not cause automatic restart from step 0.
- Timers start from their defined inactive initialization states.

### A4 — Output-interlock rules

- `fill_valve` is TRUE only during Filling and only while `stop`, `LSH`, and `LSHH` are all FALSE.
- `fill_valve` is FALSE in step 0 and Pause.
- `discharge_valve` is always FALSE.
- A TRUE `stop` forces both output commands FALSE in the same control scan, independently of timer outputs.

## Physical I/O allocation

| Logical signal | Mapped plant tag | OpenPLC address |
|---|---|---|
| Raw source of `start` | `StartCommand` | `%IX100.0` |
| `stop` | `StopCommand` | `%IX100.1` |
| `LSH` | `LSH` | `%IX100.2` |
| `LSHH` | `LSHH` | `%IX100.3` |
| `fill_valve` | `FillValve` | `%QX100.0` |
| `discharge_valve` | `DischargeValve` | `%QX100.1` |

The Factory I/O driver maps these tags through the Modbus TCP interface.

**High-high constraint:** Normal termination occurs at `LSH`; the `LSHH` interlock is a defensive backstop, not an alternative normal stopping point. Guaranteeing that 2.7 m is never reached also requires sufficient physical margin for scan and communication latency, valve closure time, and residual inflow after `LSH` detection.
