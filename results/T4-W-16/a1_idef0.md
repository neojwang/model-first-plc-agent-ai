## 1. Model boundary and conventions

**A0 — Control the tank level** is the context function. Its decomposition consists of **A1–A5** below. In standard IDEF0 diagram numbering, the context diagram containing A0 is **A-0**, and its decomposition diagram is **A0**.

- **Inputs** are information transformed by a function.
- **Controls** govern how the function operates.
- **Outputs** are the information or commands produced.
- **Mechanisms** are the resources that perform the function.

All function names below are verb phrases; arrow labels are noun phrases. Identifiers in backticks retain the required vocabulary.

### Engineering interpretation

Use the register-equivalent level scale:

| Quantity | Value |
|---|---:|
| Measuring span, `h_span` | 1000 counts = 10 V |
| Target level, `h_sp = h_target` | 800 counts |
| Overfill limit, `h_max` | 900 counts |
| Tolerance, `eps` | 20 counts |
| Required hold time, `t_h` | 10 s |
| Discharge command during regulation | 400 counts = 4 V |
| Fill command range | 0–1000 counts |

Step 0 means **both analog output commands are zero**, rather than leaving previous output values unchanged.

## 2. A0 context and child-function ICOM model

Each semicolon-separated item in an ICOM cell is a separate named arrow.

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control the tank level** | StartCommand sample; StopCommand sample; LevelMeter sample | I/O address map; FULL_SCALE value; Level-control parameters; Start-event rule; Stop-priority rule; Step-sequence rules; PID saturation rule; Integration-suspension rule; Continuous-hold rule; Initial-state rule | FillValve command; DischargeValve command | OpenPLC Runtime; PLC scan clock; PLC state memory; Modbus TCP interface; Factory I/O Level Control scene |
| **A1** | **Acquire commands and level feedback** | StartCommand sample; StopCommand sample; LevelMeter sample | I/O address map; FULL_SCALE value; Start-event rule | Start event `start`; Stop condition `stop`; Measured level `h` | OpenPLC input image; Modbus TCP interface; Previous-command memory |
| **A2** | **Evaluate level conditions and settling duration** | Measured level `h` | Level-control parameters; Regulation status; Stop condition `stop`; Continuous-hold rule | Level error `e`; Level region `r`; Settling condition `settled` | PLC arithmetic services; PLC scan clock; Hold-timer memory |
| **A3** | **Select the operating step** | Start event `start`; Stop condition `stop`; Level region `r`; Settling condition `settled` | Initial-state rule; Step-sequence rules; Stop-priority rule | Operating step; Regulation status; Fill activation `fill_valve`; Discharge activation `discharge_valve` | PLC sequence logic; Operating-step memory |
| **A4** | **Calculate the bounded PID demand** | Level error `e` | Regulation status; PID gains; PID saturation rule; Integration-suspension rule; Scan interval | Bounded fill demand | PLC arithmetic services; PID state memory; PLC scan clock |
| **A5** | **Apply the valve commands** | Bounded fill demand | Fill activation `fill_valve`; Discharge activation `discharge_valve`; Stop condition `stop`; FULL_SCALE value; Discharge-opening setting; Stop-priority rule | FillValve command; DischargeValve command | OpenPLC output image; Modbus TCP interface; Factory I/O analog valve interfaces |

### Control-arrow contents

- **I/O address map:**  
  `StartCommand → %IX100.0`; `StopCommand → %IX100.1`; `LevelMeter → %IW100`; `FillValve → %QW100`; `DischargeValve → %QW101`.
- **FULL_SCALE value:** `1000`, corresponding to 10 V with Factory I/O driver Scale = 100.
- **Level-control parameters:** `h_sp`, `h_target`, `h_max`, `eps`, `t_h`, and PID gains `Kp`, `Ti`, `Td`.
- **PID gains:** the `Kp`, `Ti`, `Td` branch of the level-control parameters.
- **Discharge-opening setting:** 40% of full scale.
- **Scan interval:** elapsed time between PID updates, obtained from the PLC timing mechanism.

## 3. Child-function connections

These are the internal arrows of the A0 decomposition.

| Source | Arrow | Destination |
|---|---|---|
| A1 | Start event `start` | A3 input |
| A1 | Stop condition `stop` | A3 input; A2 control; A5 control |
| A1 | Measured level `h` | A2 input |
| A2 | Level error `e` | A4 input |
| A2 | Level region `r` | A3 input |
| A2 | Settling condition `settled` | A3 input |
| A3 | Regulation status | A2 control; A4 control |
| A3 | Fill activation `fill_valve` | A5 control |
| A3 | Discharge activation `discharge_valve` | A5 control |
| A3 | Operating step | Internal sequence-state feedback |
| A4 | Bounded fill demand | A5 input |
| A5 | FillValve command | A0 output |
| A5 | DischargeValve command | A0 output |

The **Regulation status** feedback enables timing and PID execution only during regulation. IDEF0 arrows describe functional dependencies, not PLC instruction execution order.

## 4. Behavioral contracts

### A1 — Acquire commands and level feedback

- `start` is TRUE for exactly the scan containing a detected press of `StartCommand`; holding the button does not produce repeated events.
- `stop` reflects the current `StopCommand` value.
- `h` is the level measurement expressed on the register-equivalent scale.

### A2 — Evaluate level conditions and settling duration

Compute:

\[
e = h_{sp}-h
\]

Classify the level using exactly these region values:

| Condition | Level region `r` |
|---|---|
| `h < h_target` | `LOW` |
| `h_target <= h < h_max` | `MID` |
| `h >= h_max` | `HIGH` |

`settled` becomes TRUE only after `|e| <= eps` has remained continuously TRUE for 10 s **during regulation**. Reset the hold timer whenever:

- `|e| > eps`;
- regulation is inactive; or
- `stop` is TRUE.

### A3 — Select the operating step

| Current step | Receptivity | Resulting step | `fill_valve` | `discharge_valve` |
|---|---|---|---|---|
| Any step | `stop` | Step 0 | FALSE | FALSE |
| Step 0 | `NOT stop AND start AND r <> HIGH` | Regulation step | TRUE | TRUE |
| Step 0 | Otherwise | Step 0 | FALSE | FALSE |
| Regulation step | `NOT stop AND (settled OR r = HIGH)` | Step 0 | FALSE | FALSE |
| Regulation step | `NOT stop AND NOT settled AND r <> HIGH` | Regulation step | TRUE | TRUE |

**Priority:** `stop` overrides every other condition. A start event while `r = HIGH` leaves the system in step 0, avoiding any valve activation at or above the overfill limit.

Returning to step 0 requires a new `start` event before another regulation cycle.

### A4 — Calculate the bounded PID demand

While regulation is active:

- Calculate the PID demand from `e` using `Kp`, `Ti`, and `Td`.
- Clamp the demand to **0–100%**.
- Suspend integration while the output is clamped.
- Preserve the distinction between PID state and the externally applied valve command.

While regulation is inactive, PID integration is suspended. The requirement does not specify whether PID state is retained or reset between cycles; that policy must be selected before implementation.

### A5 — Apply the valve commands

| Condition | FillValve command | DischargeValve command |
|---|---:|---:|
| `stop = TRUE` | 0 | 0 |
| `stop = FALSE` and activation TRUE | Bounded fill demand × FULL_SCALE | 0.4 × FULL_SCALE = 400 |
| Respective activation FALSE | 0 | 0 |

Here, the respective activation identifiers are:

- `fill_valve`: TRUE while the PID drives the fill valve;
- `discharge_valve`: TRUE while the discharge valve is held at 40%.

These Boolean activation identifiers are **not** the analog output-register values.
