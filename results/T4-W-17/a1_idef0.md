## 1. Model boundary and conventions

**A0 — Control the tank level** is the requested context function. Its decomposition consists of **A1–A5** below. In standard IDEF0 diagram numbering, the context diagram is normally designated **A-0**, and the diagram containing A1–A5 is designated **A0**.

The model boundary is the PLC control application. The Factory I/O tank and operator are external; OpenPLC executes the application and exchanges I/O with Factory I/O over Modbus TCP.

- **Inputs** are information transformed by a function.
- **Controls** are conditions, rules, or parameters governing that transformation.
- **Outputs** are the resulting information or commands.
- **Mechanisms** are the resources implementing the function.
- All function names below are verb phrases; arrow labels are noun phrases or the required identifiers.

## 2. IDEF0 ICOM model

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control the tank level** | StartCommand signal; StopCommand signal; LevelMeter reading | I/O mapping specification; FULL_SCALE value; Level parameter set; PID parameter set; Cycle transition rules; Output safety rules; PID saturation and integration rules | FillValve command; DischargeValve command; `fill_valve`; `discharge_valve` | OpenPLC runtime; PLC application; Modbus TCP connection; Factory I/O driver |
| **A1** | **Interpret commands and level measurements** | StartCommand signal; StopCommand signal; LevelMeter reading | I/O mapping specification; FULL_SCALE value; Level parameter set; Start-edge rule; Level-region rules | `start`; `stop`; Level value **h**; Level error **e**; `r` | PLC input image; Input interpretation logic; Rising-edge detector |
| **A2** | **Qualify the settling interval** | Level error **e** | `fill_valve`; Tolerance value **eps**; Hold-time value **t_h**; Timer reset rule | `settled` | PLC scan clock; Non-retentive on-delay timer |
| **A3** | **Supervise the regulation cycle** | `start`; `stop`; `settled`; `r` | Initial-step rule; Cycle transition rules; Stop-priority rule | `fill_valve`; `discharge_valve`; Cycle step state | Cycle sequencer; Step-state memory |
| **A4** | **Compute the bounded fill demand** | Level error **e** | `fill_valve`; PID parameter set; PID execution interval; Demand limits; Integration suspension rule | Bounded fill demand | PID calculation logic; PID state memory; PLC scan clock |
| **A5** | **Generate valve output commands** | Bounded fill demand | `fill_valve`; `discharge_valve`; FULL_SCALE value; Discharge opening value; Output safety rules; I/O mapping specification | FillValve command; DischargeValve command | Output scaling logic; PLC output image; Modbus TCP connection; Factory I/O driver |

### Control-arrow definitions

| Control arrow | Definition |
|---|---|
| **I/O mapping specification** | StartCommand → `%IX100.0` BOOL; StopCommand → `%IX100.1` BOOL; LevelMeter → `%IW100` INT; FillValve → `%QW100` INT; DischargeValve → `%QW101` INT. Factory I/O driver Scale = 100. |
| **FULL_SCALE value** | `FULL_SCALE = 1000`, corresponding to 10 V. |
| **Level parameter set** | `h_span = 10 V` equivalent; `h_sp = h_target = 0.8 h_span`; `h_max = 0.9 h_span`; `eps = 0.02 h_span`. |
| **PID parameter set** | `Kp`, `Ti`, `Td`, with consistent units and a defined PID convention. |
| **Start-edge rule** | `start` is TRUE only in the scan detecting a rising edge of StartCommand. |
| **Level-region rules** | `r = LOW` for `h < h_target`; `r = MID` for `h_target <= h < h_max`; `r = HIGH` for `h >= h_max`. |
| **Timer reset rule** | Reset the settling interval whenever regulation is inactive or `|e| > eps`. |
| **Initial-step rule** | Step 0 is the initial state; both valve commands are zero. |
| **Cycle transition rules** | Enter regulation on `start`; leave regulation on `settled` or `r = HIGH`. |
| **Stop-priority rule** | `stop` overrides starting and continued regulation and forces step 0. |
| **Demand limits** | Fill demand is limited to 0–100%. |
| **Integration suspension rule** | Suspend integral accumulation while the PID output is clamped. |
| **Discharge opening value** | 40% opening during regulation, equivalent to 4 V or register value 400. |
| **Output safety rules** | Both valve commands are zero in step 0 and whenever `stop` is TRUE. |

## 3. Child-function connections

These connections identify the internal arrows and feedback paths of the decomposition.

| Source | Arrow | Destination |
|---|---|---|
| A0 boundary | StartCommand signal; StopCommand signal; LevelMeter reading | A1 |
| A1 | `start`; `stop`; `r` | A3 |
| A1 | Level error **e** | A2 and A4 |
| A2 | `settled` | A3 |
| A3 | `fill_valve` | A2, A4, and A5 |
| A3 | `discharge_valve` | A5 |
| A4 | Bounded fill demand | A5 |
| A5 | FillValve command; DischargeValve command | A0 boundary |
| A3 | `fill_valve`; `discharge_valve` | A0 boundary |
| A1 | Level value **h** | Internal measurement/reference point |
| A3 | Cycle step state | Internal state/reference point |

The **Level value h** and **Cycle step state** reference points may be shown as tunneled diagnostic arrows if they are not exposed outside the application.

## 4. Functional semantics

### A1 — Interpret commands and level measurements

Use a common level scale throughout the model:

\[
h=\frac{\text{LevelMeter}}{\text{FULL\_SCALE}}h_{\text{span}},
\qquad
e=h_{sp}-h
\]

The equivalent register-domain quantities are:

| Quantity | Register-domain value |
|---|---:|
| Target level | 800 |
| Overfill limit | 900 |
| Tolerance | ±20 |
| Constant discharge command | 400 |

`stop` follows StopCommand directly. `start` is a one-scan event, not a maintained start request.

### A2 — Qualify the settling interval

`settled` becomes TRUE only after **10 continuous seconds** during which:

- `fill_valve` is TRUE, indicating active regulation; and
- `|e| <= eps`.

Leaving the tolerance band or leaving regulation resets the interval. Time spent in tolerance while idle does not qualify.

### A3 — Supervise the regulation cycle

| Current step | Condition | Resulting step | `fill_valve` | `discharge_valve` |
|---|---|---|---|---|
| Any | `stop = TRUE` | Step 0 | FALSE | FALSE |
| Step 0 | No `start` event | Step 0 | FALSE | FALSE |
| Step 0 | `start`, with `stop = FALSE` and `r ≠ HIGH` | Regulation step | TRUE | TRUE |
| Step 0 | `start`, with `r = HIGH` | Step 0 | FALSE | FALSE |
| Regulation step | `settled` or `r = HIGH` | Step 0 | FALSE | FALSE |
| Regulation step | Otherwise | Regulation step | TRUE | TRUE |

A start event at or above the overfill limit must not produce an opening pulse. Following completion, a new start event is required; a continuously held StartCommand does not restart the cycle.

### A4 — Compute the bounded fill demand

During regulation:

\[
u_{\text{raw}}=\operatorname{PID}(e;K_p,T_i,T_d)
\]

\[
u=\operatorname{clamp}(u_{\text{raw}},0,100\%)
\]

Integral accumulation is suspended whenever the output is clamped. A zero bounded demand does **not** make `fill_valve` FALSE: that identifier indicates that PID control is active, rather than that the physical valve opening is nonzero.

The PID form, execution interval, and initial/reset state policy must be selected before implementation. They must not alter the specified stop, completion, or output-limiting behavior.

### A5 — Generate valve output commands

| Operating condition | FillValve command | DischargeValve command |
|---|---:|---:|
| Regulation active | Integer-scaled bounded fill demand, 0–1000 | 400 |
| Step 0, completed cycle, overfill termination, or stop | 0 | 0 |

“Step 0 drives no output” is modeled as **explicit zero commands**, not retention of previously written analog values. Stop and termination conditions must therefore affect the output commands in the same control scan in which they are recognized.
