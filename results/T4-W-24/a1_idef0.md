## 1. Model scope and notation

**A0 — Control tank level** is the context function. Its decomposition contains functions **A1–A5**.

In FIPS 183 notation, the context diagram containing A0 is designated **A-0**; the diagram containing its children A1–A5 is designated **A0**.

- **Inputs** are information transformed by a function.
- **Controls** govern when or how the function operates.
- **Outputs** are information or commands produced.
- **Mechanisms** are the resources that perform the function.

All arrow labels below are noun phrases or the exact required identifiers. The identifiers `fill_valve` and `discharge_valve` denote Boolean operating enables, **not** analog valve-command values.

## 2. Context function

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| A0 | Control tank level | Start-command sample (`StartCommand`); stop-command sample (`StopCommand`); level-meter sample (`LevelMeter`) | I/O mapping; `FULL_SCALE = 1000`; measuring span `h_span`; level set point `h_sp = h_target = 0.8 h_span`; overfill limit `h_max = 0.9 h_span`; tolerance band `eps = 0.02 h_span`; hold duration `t_h = 10 s`; PID parameters `Kp`, `Ti`, `Td`; discharge opening of 40%; operating sequence; stop priority; PID saturation and integration-suspension rules | Fill-valve command (`FillValve`); discharge-valve command (`DischargeValve`) | OpenPLC Runtime; PLC scan clock; Modbus TCP connection; Factory I/O Modbus TCP slave interface; Factory I/O tank, level meter, and valves |

### Boundary I/O mapping

| Arrow | PLC address and type | Meaning |
|---|---|---|
| Start-command sample (`StartCommand`) | `%IX100.0 : BOOL` | Start-button state |
| Stop-command sample (`StopCommand`) | `%IX100.1 : BOOL` | Stop-button state |
| Level-meter sample (`LevelMeter`) | `%IW100 : INT` | Analog level measurement; 0–1000 corresponds to 0–10 V |
| Fill-valve command (`FillValve`) | `%QW100 : INT` | Fill opening; 0–1000 corresponds to 0–100% |
| Discharge-valve command (`DischargeValve`) | `%QW101 : INT` | Discharge opening; commanded to 0 or 400 |

The Factory I/O driver uses **Scale = 100**, so **1000 register units correspond to 10 V**.

## 3. Child-function decomposition

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| A1 | Acquire and normalize process signals | Start-command sample (`StartCommand`); stop-command sample (`StopCommand`); level-meter sample (`LevelMeter`) | I/O mapping; `FULL_SCALE`; measuring span `h_span`; rising-edge definition | `start`; `stop`; measured level `h` | OpenPLC input image; Modbus TCP input exchange; edge-history memory |
| A2 | Evaluate level conditions | Measured level `h` | Level set point `h_sp = h_target`; overfill limit `h_max`; tolerance band `eps`; hold duration `t_h`; `fill_valve` | Level error `e`; `r`; `settled` | OpenPLC arithmetic and comparison facilities; scan clock; hold timer |
| A3 | Supervise regulation sequence | — | `start`; `stop`; `r`; `settled`; initial-step rule; stop priority; completion rule | `fill_valve`; `discharge_valve` | OpenPLC execution engine; sequence-state memory |
| A4 | Calculate bounded PID demand | Level error `e` | `fill_valve`; PID parameters `Kp`, `Ti`, `Td`; controller sampling interval; opening limits of 0–100%; integration-suspension rule | Bounded fill-opening demand | OpenPLC arithmetic facilities; PID-state memory; scan clock |
| A5 | Apply valve commands | Bounded fill-opening demand | `fill_valve`; `discharge_valve`; `FULL_SCALE`; discharge opening of 40%; zero-output rule | Fill-valve command (`FillValve`); discharge-valve command (`DischargeValve`) | OpenPLC output image; Modbus TCP output exchange; Factory I/O analog valve interfaces |

Here, `start`, `stop`, `r`, and `settled` are **controls** of A3 because they govern its state transitions.

## 4. Internal arrow definitions and connections

| Arrow | Source → destination | Definition |
|---|---|---|
| `start` | A1 → A3 | TRUE for one scan on a rising edge of `StartCommand` |
| `stop` | A1 → A3 | Current Boolean state of `StopCommand` |
| Measured level `h` | A1 → A2 | `h = (LevelMeter / FULL_SCALE) h_span`, evaluated without integer-division truncation |
| Level error `e` | A2 → A4 | `e = h_sp − h` |
| `r` | A2 → A3 | `LOW` for `h < h_target`; `MID` for `h_target ≤ h < h_max`; `HIGH` for `h ≥ h_max` |
| `settled` | A2 → A3 | TRUE after `abs(e) ≤ eps` has remained continuously true for `t_h` during regulation |
| `fill_valve` | A3 → A2, A4, A5 | TRUE while regulation authorizes PID control of the fill valve |
| `discharge_valve` | A3 → A5 | TRUE while regulation authorizes the constant 40% discharge opening |
| Bounded fill-opening demand | A4 → A5 | PID opening demand limited to 0–100% |

The enable arrows feeding back from A3 to A2 and A4 represent **state-dependent control**, not a requirement to insert a one-scan delay.

## 5. Functional operating rules

### A1 — Acquire and normalize process signals

- Detect `start` from the rising edge of `StartCommand`.
- Pass `StopCommand` as `stop`; stopping is level-sensitive, not edge-sensitive.
- Convert the level-meter register into the same units used for `h_sp`, `h_max`, and `eps`.

Equivalent register-domain thresholds are:

- Target: **800**
- Overfill limit: **900**
- Tolerance: **±20**

### A2 — Evaluate level conditions

- Calculate `e` and classify `r`.
- Accumulate hold time only while `fill_valve` is TRUE and `abs(e) ≤ eps`.
- Reset the hold timer when regulation is inactive or the level leaves the tolerance band.
- Assert `settled` only after an uninterrupted **10 s** interval.

### A3 — Supervise regulation sequence

| Current condition | Result |
|---|---|
| Initial condition | Step 0; `fill_valve = FALSE`; `discharge_valve = FALSE` |
| `stop = TRUE`, regardless of state or other receptivities | Step 0; both enables FALSE |
| Step 0 with `start = TRUE`, `stop = FALSE`, and `r ≠ HIGH` | Regulation active; both enables TRUE |
| Regulation active with `settled = TRUE` or `r = HIGH` | Step 0; both enables FALSE |
| Step 0 without an accepted `start` | Remain in step 0; both enables FALSE |
| Regulation active without a stopping or completion condition | Remain in regulation; both enables TRUE |

**Priority:** `stop` overrides every other condition. An overfill condition also prevents valve actuation on a coincident start. Holding the start button does not cause automatic restarting because `start` is a one-scan event.

### A4 — Calculate bounded PID demand

- Execute PID regulation while `fill_valve` is TRUE, using `e = h_sp − h`.
- Clamp the PID opening demand to **0–100%**.
- Suspend integration whenever the unconstrained PID demand is outside those limits and the output is clamped.
- Do not advance the PID integrator while regulation is inactive.

PID-state initialization or reinitialization on a new run remains a detailed-design decision; the task does not specify a particular reset or bumpless-transfer policy.

### A5 — Apply valve commands

- With `fill_valve = TRUE`, scale the bounded PID demand to **0–1000** for `FillValve`.
- With `discharge_valve = TRUE`, command `DischargeValve = 400`.
- With either enable FALSE, command its corresponding analog output to **0**.
- In step 0, including every scan with `stop = TRUE`, command **both outputs to 0**.

Thus, “step 0 drives no output” is implemented as explicit zero commands, rather than leaving previous valve commands latched.
