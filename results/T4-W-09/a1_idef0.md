## A0 context function — Control tank level

**Scope:** The OpenPLC controller for the Factory I/O **Level Control** scene in analog configuration. The tank, valves, level sensor, and operator are outside the controller boundary.

Arrow names below are noun phrases; function names are verb phrases. The required identifiers `start`, `stop`, `settled`, `r`, `fill_valve`, and `discharge_valve` are preserved exactly.

### Context ICOM

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control tank level** | Start-command signal (`StartCommand`, `%IX100.0`); stop-command signal (`StopCommand`, `%IX100.1`); level-meter value (`LevelMeter`, `%IW100`) | I/O mapping and analog scaling; `FULL_SCALE = 1000`; level span `h_span`; target `h_sp = h_target = 0.8 h_span`; overfill limit `h_max = 0.9 h_span`; tolerance `eps = 0.02 h_span`; hold time `t_h = 10 s`; PID gains `Kp`, `Ti`, `Td`; discharge opening of 40%; initial-step, stop-priority, termination, saturation, and integration-suspension rules | Fill-valve command (`FillValve`, `%QW100`); discharge-valve command (`DischargeValve`, `%QW101`) | OpenPLC Runtime; PLC cyclic task and clock; Modbus TCP communication with the Factory I/O slave device |

## A0 decomposition

The child functions are:

- **A1 — Acquire commands and classify level**
- **A2 — Qualify level settling**
- **A3 — Manage regulation steps**
- **A4 — Calculate bounded PID demand**
- **A5 — Apply valve commands**

### Child-function ICOM

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A1** | **Acquire commands and classify level** | Start-command signal (`StartCommand`); stop-command signal (`StopCommand`); level-meter value (`LevelMeter`) | I/O mapping; `FULL_SCALE`; `h_span`; `h_sp`; `h_target`; `h_max`; rising-edge detection rule; level-region boundaries | Start event (`start`); stop status (`stop`); measured level (`h`); level error (`e`); level region (`r`) | OpenPLC input image; Modbus TCP input interface; rising-edge memory; scaling and comparison operations |
| **A2** | **Qualify level settling** | Level error (`e`) | Regulation-step status; stop status (`stop`); tolerance (`eps`); hold time (`t_h`); continuous-in-band timing rule; timer-reset rule | Settling status (`settled`) | PLC clock; nonretentive on-delay timing mechanism |
| **A3** | **Manage regulation steps** | Start event (`start`); stop status (`stop`); settling status (`settled`); level region (`r`) | Initial step 0; step-transition rules; stop priority; overfill priority; startup initialization rule | Regulation-step status; PID-drive enable (`fill_valve`); constant-discharge enable (`discharge_valve`) | PLC cyclic task; step-state memory |
| **A4** | **Calculate bounded PID demand** | Level error (`e`) | PID-drive enable (`fill_valve`); PID gains (`Kp`, `Ti`, `Td`); execution interval; output limits of 0–100%; integration-suspension rule | Bounded fill-opening demand | PID calculation mechanism; PID state memory; saturation logic; PLC time base |
| **A5** | **Apply valve commands** | Bounded fill-opening demand | PID-drive enable (`fill_valve`); constant-discharge enable (`discharge_valve`); stop status (`stop`); `FULL_SCALE`; discharge opening of 40%; zero-output rule; integer-conversion rule | Fill-valve command (`FillValve`, `%QW100`); discharge-valve command (`DischargeValve`, `%QW101`) | OpenPLC output image; analog-command conversion; Modbus TCP output interface |

## Internal arrow connections

These connections define the decomposition without implying that IDEF0 itself is a scan-order or sequence diagram.

| Arrow | Source | Destination |
|---|---|---|
| Start event (`start`) | A1 | A3 input |
| Stop status (`stop`) | A1 | A2, A3, and A5 controls/inputs as listed above |
| Measured level (`h`) | A1 | Internal level representation used to derive `e` and `r` within A1 |
| Level error (`e`) | A1 | A2 and A4 inputs |
| Level region (`r`) | A1 | A3 input |
| Settling status (`settled`) | A2 | A3 input |
| Regulation-step status | A3 | A2 control |
| PID-drive enable (`fill_valve`) | A3 | A4 and A5 controls |
| Constant-discharge enable (`discharge_valve`) | A3 | A5 control |
| Bounded fill-opening demand | A4 | A5 input |
| Fill-valve command; discharge-valve command | A5 | A0 boundary outputs |

The measured level `h` is an internal A1 result, not an additional physical input or required external output.

## Behavioral controls attached to the model

### 1. Signal interpretation — A1

- `start` is TRUE **only for the scan containing the rising edge** of `StartCommand`.
- `stop` is the current Boolean value of `StopCommand`.
- Analog scaling:
  \[
  h=\frac{\text{LevelMeter}}{\text{FULL\_SCALE}}\,h_{\text{span}},
  \qquad e=h_{sp}-h
  \]
- `r` has exactly these regions:
  - `LOW`: \(h<h_{target}\)
  - `MID`: \(h_{target}\le h<h_{max}\)
  - `HIGH`: \(h\ge h_{max}\)

At the specified scaling, the target, overfill limit, and tolerance correspond to **800**, **900**, and **20** level-register counts, respectively.

### 2. Settling qualification — A2

`settled` becomes TRUE only after \(|e|\le eps\) has remained continuously true for **10 s during regulation**.

The elapsed hold time is cleared when:

- The error leaves the tolerance band;
- Regulation ends; or
- `stop` is TRUE.

Thus, separate visits to the tolerance band cannot accumulate toward the hold time.

### 3. Step management — A3

| Current condition | Resulting step | `fill_valve` | `discharge_valve` |
|---|---:|---:|---:|
| Initialization | 0 | FALSE | FALSE |
| `stop = TRUE`, regardless of other conditions | 0 | FALSE | FALSE |
| Step 0, `start = TRUE`, `stop = FALSE`, and `r ≠ HIGH` | 1 — regulation | TRUE | TRUE |
| Step 1, `stop = FALSE`, `settled = FALSE`, and `r ≠ HIGH` | 1 — regulation | TRUE | TRUE |
| Step 1 with `settled = TRUE` or `r = HIGH` | 0 | FALSE | FALSE |
| Step 0 without an accepted `start` | 0 | FALSE | FALSE |

**Priority:** `stop` overrides every other condition. An overfill condition prevents valve activation even if `start` occurs in the same scan. A start event during regulation is not queued for a later restart.

### 4. PID calculation — A4

While `fill_valve = TRUE`:

- Calculate PID demand from \(e=h_{sp}-h\).
- Limit the fill-opening demand to **0–100%**.
- Suspend integration whenever the unconstrained demand is clamped by either limit.

While `fill_valve = FALSE`, the PID does not command the valve or continue active regulation integration. Any PID-state initialization policy must be defined during detailed design; it must not override the zero-output requirements.

### 5. Output application — A5

- When `fill_valve = TRUE`, convert the bounded PID percentage into a register command from **0 to 1000**.
- When `discharge_valve = TRUE`, command:
  \[
  \text{DischargeValve}=0.4\,\text{FULL\_SCALE}=400
  \]
- When either enable is FALSE, its corresponding valve command is **0**.
- Whenever `stop = TRUE`, both commands are **0**, independently of the PID demand.

Here, `fill_valve` and `discharge_valve` are the required **Boolean operating enables**, not the analog output registers. Step 0 therefore “drives no output” by explicitly commanding both analog outputs to zero rather than retaining their previous values.
