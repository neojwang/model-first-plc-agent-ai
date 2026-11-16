## 1. Model boundary and conventions

**A0 — Control the tank level** is the context function. Its decomposition consists of **A1–A5** below.

- **Inputs** are data transformed by a function.
- **Controls** are rules, parameters, and conditions governing a function.
- **Outputs** are results produced by a function.
- **Mechanisms** are execution resources.

The model distinguishes the required logical outputs from the physical analog commands:

- **`fill_valve`**: TRUE while the PID drives the fill valve.
- **`discharge_valve`**: TRUE while the discharge valve is held at 40%.
- **Fill-valve register value** and **discharge-valve register value**: the physical analog commands written to `%QW100` and `%QW101`.

The identifiers **`start`**, **`stop`**, **`settled`**, and **`r`** are used exactly as specified.

## 2. A0 context function

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control the tank level** | StartCommand signal; StopCommand signal; LevelMeter register value | I/O mapping; FULL_SCALE; measuring span; level target; overfill limit; tolerance band; hold time; PID gains; initial-step rule; start-event rule; stop-priority rule; completion rule; output-limiting rule; integration-suspension rule; discharge-opening rule | Fill-valve register value; discharge-valve register value | OpenPLC Runtime; cyclic PLC task; Modbus TCP connection; Factory I/O driver; PID calculation facility; timer facility |

### Context controls

| Control arrow | Definition |
|---|---|
| I/O mapping | StartCommand: `%IX100.0`; StopCommand: `%IX100.1`; LevelMeter: `%IW100`; FillValve: `%QW100`; DischargeValve: `%QW101` |
| FULL_SCALE | `1000`, corresponding to 10 V; Factory I/O driver Scale = 100 |
| Measuring span | \(h_{\text{span}}\), represented by the level meter’s 0–10 V range |
| Level target | \(h_{sp}=h_{\text{target}}=0.8h_{\text{span}}\) |
| Overfill limit | \(h_{\max}=0.9h_{\text{span}}\) |
| Tolerance band | \(\varepsilon=0.02h_{\text{span}}\) |
| Hold time | \(t_h=10\,s\) |
| PID gains | \(K_p,T_i,T_d\); numerical values are not specified |
| Initial-step rule | Step 0 is the initial, inactive step; both physical outputs are zero |
| Start-event rule | `start` is TRUE only during the scan containing a rising edge of StartCommand |
| Stop-priority rule | `stop` overrides starting and regulation; both physical outputs become zero |
| Completion rule | Regulation ends when `settled` is TRUE or `r = HIGH` |
| Output-limiting rule | PID valve demand is limited to 0–100% |
| Integration-suspension rule | PID integration is suspended while its output is clamped |
| Discharge-opening rule | Discharge opening is 40% during regulation and zero otherwise |

## 3. A0 decomposition

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|---|
| **A1** | **Acquire and normalize plant signals** | StartCommand signal; StopCommand signal; LevelMeter register value | I/O mapping; FULL_SCALE; measuring span; start-event rule | `start`; `stop`; measured level | OpenPLC input image; Modbus TCP connection; Factory I/O driver; rising-edge memory |
| **A2** | **Evaluate level conditions** | Measured level | Level target; overfill limit; tolerance band; hold time; regulation status; timer-reset rule | Level error; `r`; `settled` | PLC arithmetic and comparison facilities; timer facility |
| **A3** | **Manage the regulation sequence** | `start`; `stop`; `settled`; `r` | Initial-step rule; stop-priority rule; completion rule; sequence-transition rules | Active step; regulation status; `fill_valve`; `discharge_valve` | PLC sequence logic; retained scan-to-scan step memory |
| **A4** | **Calculate the bounded PID demand** | Level error | PID gains; PLC cycle interval; regulation status; output-limiting rule; integration-suspension rule | Bounded fill demand | PID calculation facility; PID state memory; cyclic PLC task |
| **A5** | **Apply the valve commands** | Bounded fill demand | `fill_valve`; `discharge_valve`; `stop`; FULL_SCALE; discharge-opening rule; zero-output rule; I/O mapping | Fill-valve register value; discharge-valve register value | PLC output image; Modbus TCP connection; Factory I/O driver |

### Child-function details

#### A1 — Acquire and normalize plant signals

- Produce `start` from the rising edge of StartCommand. A continuously held button does not generate repeated start events.
- Produce `stop` directly from StopCommand.
- Convert the level register into the measured level:

\[
h=\frac{\text{LevelMeter}}{\text{FULL\_SCALE}}h_{\text{span}}
\]

The equivalent register-domain target, overfill limit, and tolerance are **800**, **900**, and **20**, respectively.

#### A2 — Evaluate level conditions

Produce the level error:

\[
e=h_{sp}-h
\]

Produce `r` according to:

| Level condition | `r` |
|---|---|
| \(h<h_{\text{target}}\) | `LOW` |
| \(h_{\text{target}}\le h<h_{\max}\) | `MID` |
| \(h\ge h_{\max}\) | `HIGH` |

Produce `settled` only after \(|e|\le\varepsilon\) has remained continuously true for 10 seconds **during regulation**.

The **timer-reset rule** resets the accumulated hold time whenever regulation is inactive or the level leaves the tolerance band. Thus, separate intervals within the band do not accumulate.

#### A3 — Manage the regulation sequence

Step 1 denotes active regulation.

| Current step | Receptivity | Resulting step | `fill_valve` | `discharge_valve` |
|---|---|---|---|---|
| Any | `stop` | Step 0 | FALSE | FALSE |
| Step 0 | `start` AND NOT `stop` | Step 1 | TRUE | TRUE |
| Step 0 | NOT `start` AND NOT `stop` | Step 0 | FALSE | FALSE |
| Step 1 | NOT `stop` AND (`settled` OR `r = HIGH`) | Step 0 | FALSE | FALSE |
| Step 1 | NOT `stop` AND NOT `settled` AND `r ≠ HIGH` | Step 1 | TRUE | TRUE |

**Priority:** `stop` is highest priority. The high-level condition also inhibits active valve commands: starting with `r = HIGH` must not cause a one-scan valve-opening pulse.

The **regulation status** is active only while Step 1 is effective after these priority conditions have been evaluated.

#### A4 — Calculate the bounded PID demand

During regulation:

\[
u_{\text{bounded}}=\operatorname{clamp}(u_{\text{PID}},0,100\%)
\]

- Use \(e=h_{sp}-h\) as the PID error.
- Suspend integration whenever output limiting is active.
- Do not advance integration while regulation is inactive.

PID tuning values and any additional restart-state policy remain implementation parameters; they are not supplied by the task.

#### A5 — Apply the valve commands

| Condition | Fill-valve register value | Discharge-valve register value |
|---|---:|---:|
| `stop` | 0 | 0 |
| NOT `stop` AND `fill_valve` | \(u_{\text{bounded}}\times\text{FULL\_SCALE}/100\%\) | Determined by `discharge_valve` |
| NOT `stop` AND NOT `fill_valve` | 0 | Determined by `discharge_valve` |
| NOT `stop` AND `discharge_valve` | Determined by `fill_valve` | \(0.4\times\text{FULL\_SCALE}=400\) |
| NOT `stop` AND NOT `discharge_valve` | Determined by `fill_valve` | 0 |

The **zero-output rule** explicitly writes zero to both analog outputs in Step 0; it does not leave previous output values unchanged.

## 4. Internal arrow connections

| Source | Arrow | Destination |
|---|---|---|
| A1 | `start`; `stop` | A3 inputs |
| A1 | `stop` | A5 control |
| A1 | Measured level | A2 input |
| A2 | Level error | A4 input |
| A2 | `r`; `settled` | A3 inputs |
| A3 | Regulation status | A2 and A4 controls |
| A3 | `fill_valve`; `discharge_valve` | A5 controls |
| A4 | Bounded fill demand | A5 input |
| A5 | Fill-valve register value; discharge-valve register value | A0 boundary outputs |

These arrows describe functional dependencies, not a mandatory software execution order. The eventual scan design must nevertheless preserve stop priority, timely completion handling, and zero outputs whenever regulation is inactive.
