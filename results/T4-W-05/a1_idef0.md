## IDEF0 model

**Scope:** Control the Factory I/O analog Level Control tank through OpenPLC and Modbus TCP. The tank and its physical response are outside the controller’s functional boundary.

All function names below are verb phrases. Arrow labels are noun phrases; the required identifiers `start`, `stop`, `settled`, `r`, `fill_valve`, and `discharge_valve` are retained exactly.

### A0 — Control tank level

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control tank level** | StartCommand signal; StopCommand signal; LevelMeter register value | I/O address map; FULL_SCALE calibration; level set point; overfill limit; tolerance band; hold duration; PID gains; PID saturation and integration-suspension rules; operating-sequence rules; stop-priority rule | FillValve register command; DischargeValve register command | OpenPLC Runtime; PLC scan clock; Modbus TCP connection; Factory I/O slave interface |

### Decomposition of A0

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A1** | **Interpret commands and level measurement** | StartCommand signal; StopCommand signal; LevelMeter register value | Input address map; FULL_SCALE calibration; measuring span; level target; overfill limit; rising-edge detection rule | `start`; `stop`; measured level; `r` | OpenPLC input image; edge-detection memory; arithmetic and comparison operations |
| **A2** | **Manage the operating sequence** | `start`; `stop`; `settled`; `r` | Initial-step rule; stop-priority rule; regulation-start rule; regulation-completion rule | Operating-step state; `fill_valve`; `discharge_valve` | OpenPLC execution engine; step-state memory |
| **A3** | **Compute bounded PID valve demand** | Measured level | `fill_valve`; level set point; PID gains; PID update interval; output limits; integration-suspension rule | Level error; bounded fill demand | PID calculation facility; PID state memory; PLC scan clock |
| **A4** | **Verify continuous level settling** | Level error | `fill_valve`; tolerance band; hold duration; timer-reset rule | `settled` | Non-retentive on-delay timer; PLC scan clock |
| **A5** | **Issue valve register commands** | Bounded fill demand | `fill_valve`; `discharge_valve`; FULL_SCALE calibration; discharge-opening requirement; inactive-output rule; output address map | FillValve register command; DischargeValve register command | Register-scaling operations; OpenPLC output image; Modbus TCP connection; Factory I/O slave interface |

## Arrow definitions and constraints

### External I/O and calibration

| Arrow or control | Definition |
|---|---|
| StartCommand signal | `StartCommand AT %IX100.0 : BOOL` |
| StopCommand signal | `StopCommand AT %IX100.1 : BOOL` |
| LevelMeter register value | `LevelMeter AT %IW100 : INT` |
| FillValve register command | `FillValve AT %QW100 : INT`, constrained to 0–1000 |
| DischargeValve register command | `DischargeValve AT %QW101 : INT`, either 0 or 400 |
| FULL_SCALE calibration | `FULL_SCALE = 1000` represents 10 V; Factory I/O driver Scale = 100 |
| Measured level | \(h=(\text{LevelMeter}/1000)\,h_{\text{span}}\) |
| Level set point / level target | \(h_{sp}=h_{\text{target}}=0.8h_{\text{span}}\), equivalent to register value 800 |
| Overfill limit | \(h_{\max}=0.9h_{\text{span}}\), equivalent to register value 900 |
| Tolerance band | \(\varepsilon=0.02h_{\text{span}}\), equivalent to 20 register counts |
| Hold duration | \(t_h=10\,\text{s}\) |

### Required identifier vocabulary

| Arrow | Meaning |
|---|---|
| `start` | Rising-edge event of StartCommand; TRUE only during the scan in which the button is pressed |
| `stop` | Current Boolean state of StopCommand |
| `settled` | TRUE when \(\lvert h_{sp}-h\rvert\leq\varepsilon\) has remained continuously true for 10 s during regulation |
| `r` | LOW when \(h<h_{\text{target}}\); MID when \(h_{\text{target}}\leq h<h_{\max}\); HIGH when \(h\geq h_{\max}\) |
| `fill_valve` | TRUE while PID demand controls the fill valve |
| `discharge_valve` | TRUE while the discharge valve is commanded to 40% opening |

`fill_valve` and `discharge_valve` are **Boolean operating permissions**, not analog valve magnitudes.

## Child-function coordination

The principal internal arrows are:

- **A1 → A2:** `start`, `stop`, `r`.
- **A1 → A3:** measured level.
- **A2 → A3:** `fill_valve`.
- **A2 → A4:** `fill_valve`.
- **A2 → A5:** `fill_valve`, `discharge_valve`.
- **A3 → A4:** level error.
- **A3 → A5:** bounded fill demand.
- **A4 → A2:** `settled`.
- **A5 → A0 boundary:** FillValve register command; DischargeValve register command.

The following constraints define the controls applied to those functions:

### A2 — Operating-sequence rules

| Condition | Resulting state and permissions |
|---|---|
| Initialization | Step 0; `fill_valve = FALSE`; `discharge_valve = FALSE` |
| `stop = TRUE`, in any state | Step 0; both permissions FALSE |
| Step 0, `start = TRUE`, `stop = FALSE`, and `r` other than HIGH | Regulation step; both permissions TRUE |
| Regulation step, `settled = TRUE` or `r = HIGH` | Step 0; both permissions FALSE |
| No applicable transition | Existing state retained |

Stop and overfill termination take precedence over starting or continuing regulation. A held StartCommand does not cause an automatic restart: a new `start` event is required.

### A3 — PID constraints

- Level error: \(e=h_{sp}-h\).
- PID action: positive error produces increased fill demand.
- Bounded fill demand: 0–100% opening.
- Integration is suspended while the PID output is clamped.
- PID integration is inactive when `fill_valve = FALSE`.
- PID gains are \(K_p,T_i,T_d\); their numerical tuning and the PID update interval remain implementation parameters.

### A4 — Settling constraints

The settling timer runs only while `fill_valve = TRUE` and \(\lvert e\rvert\leq\varepsilon\). It resets when either condition becomes false. Thus, separate visits to the tolerance band do not accumulate toward the 10 s requirement.

### A5 — Output constraints

- With `fill_valve = TRUE`, the bounded PID demand is scaled to the FillValve register range 0–1000.
- With `discharge_valve = TRUE`, the DischargeValve register command is \(0.4\times1000=400\), corresponding to 4 V.
- A FALSE permission forces its corresponding register command to zero.
- Step 0 therefore has **no active valve output**: both registers are explicitly zero, rather than retaining previous values.
