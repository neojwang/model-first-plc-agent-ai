## IDEF0 scope and conventions

The context function is **A0 — Control tank level**. Its decomposition comprises **A1–A5**.

- **Inputs** are signals or data transformed by a function.
- **Controls** are rules, parameters, or conditions governing a function.
- **Outputs** are the resulting signals or data.
- **Mechanisms** are the resources performing the function.
- Arrow labels below are noun phrases. The prescribed identifiers `start`, `stop`, `settled`, `r`, `fill_valve`, and `discharge_valve` retain their exact spelling.

## A0 context and child-function ICOM table

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control tank level** | StartCommand signal; StopCommand signal; LevelMeter register value | Level set point `h_sp = h_target = 0.8 h_span`; overfill limit `h_max = 0.9 h_span`; tolerance `eps = 0.02 h_span`; hold duration `t_h = 10 s`; PID gains `Kp`, `Ti`, `Td`; `FULL_SCALE = 1000`; driver scale `100`; initial-step rule; start-event rule; stop-priority rule; completion rule; valve limits; integral-suspension rule; discharge-opening requirement | FillValve register command; DischargeValve register command | OpenPLC runtime; PLC scan and timebase; Modbus TCP connection; Factory I/O analog scene and driver |
| **A1** | **Interpret commands and level** | StartCommand signal; StopCommand signal; LevelMeter register value | I/O address mapping; `FULL_SCALE`; measuring span `h_span`; set point `h_sp`; target `h_target`; overfill limit `h_max`; rising-edge rule | `start`; `stop`; level error `e`; level region `r` | Input image; rising-edge memory; scaling and comparison operations |
| **A2** | **Qualify level settling** | Level error `e` | Tolerance `eps`; hold duration `t_h`; `fill_valve`; continuous-dwell rule; idle-reset rule | `settled` | PLC timer; PLC timebase; tolerance comparison |
| **A3** | **Select operating step** | `start`; `stop`; `settled`; `r` | Initial step 0; stop-priority rule; start-acceptance rule; completion rule; overfill-inhibition rule | `fill_valve`; `discharge_valve` | Step-state memory; PLC state-transition logic |
| **A4** | **Calculate bounded PID demand** | Level error `e` | `fill_valve`; PID gains `Kp`, `Ti`, `Td`; controller execution interval; output bounds of 0–100%; integral-suspension rule; controller initialization policy | Bounded fill demand | PID calculation; integral and derivative state memory; PLC timebase |
| **A5** | **Issue valve commands** | Bounded fill demand; `fill_valve`; `discharge_valve` | `stop`; `FULL_SCALE`; discharge-opening requirement of 40%; idle-zero rule; output bounds; output address mapping | FillValve register command; DischargeValve register command | Output image; integer conversion; Modbus TCP connection; Factory I/O driver |

## Child-function connections

These connections define the internal arrows of the A0 decomposition:

| Source | Arrow | Destination |
|---|---|---|
| A1 | `start` | A3 input |
| A1 | `stop` | A3 input; A5 control |
| A1 | Level error `e` | A2 input; A4 input |
| A1 | Level region `r` | A3 input |
| A2 | `settled` | A3 input |
| A3 | `fill_valve` | A2 control; A4 control; A5 input |
| A3 | `discharge_valve` | A5 input |
| A4 | Bounded fill demand | A5 input |
| A5 | FillValve register command | A0 output boundary |
| A5 | DischargeValve register command | A0 output boundary |

The command and measurement signals enter through the A0 input boundary into A1. The A0 controls and mechanisms are allocated to the child functions as shown above. These connections describe functional dependencies, **not PLC execution order**.

## Functional rules

### A1 — Interpret commands and level

Use a consistent level representation:

\[
h=\frac{\text{LevelMeter}}{\text{FULL\_SCALE}}\,h_{\text{span}},
\qquad e=h_{sp}-h
\]

- `start`: TRUE for one scan on a FALSE-to-TRUE transition of StartCommand.
- `stop`: the current StopCommand value.
- `r`:
  - `LOW` when \(h<h_{target}\)
  - `MID` when \(h_{target}\le h<h_{max}\)
  - `HIGH` when \(h\ge h_{max}\)

Thus, in register units, the target, overfill threshold, and tolerance are respectively **800**, **900**, and **20**.

### A2 — Qualify level settling

`settled` becomes TRUE only after \(|e|\le eps\) has remained continuously true for **10 s during regulation**.

Reset the dwell timer whenever regulation is inactive or \(|e|>eps\). Time accumulated before regulation must not contribute.

### A3 — Select operating step

- **Step 0:** initial and idle state; `fill_valve = FALSE`, `discharge_valve = FALSE`.
- **Regulation step:** `fill_valve = TRUE`, `discharge_valve = TRUE`.
- `stop` has highest priority and selects step 0.
- From step 0, `start` selects regulation only when `r` is not `HIGH`.
- During regulation, `settled` or `r = HIGH` selects step 0.
- A held StartCommand does not restart regulation; another `start` event is required.

The `HIGH` start inhibition applies the overfill termination condition immediately, avoiding a one-scan valve-opening pulse.

### A4 — Calculate bounded PID demand

While `fill_valve` is TRUE:

- Calculate PID demand from \(e=h_{sp}-h\).
- Limit the demand to **0–100%**.
- Suspend integration while the demand is clamped.

While `fill_valve` is FALSE, the PID must not drive the physical fill output. The precise PID form, execution interval, and integral/derivative initialization policy remain design decisions to resolve before coding.

### A5 — Issue valve commands

| Condition | FillValve `%QW100` | DischargeValve `%QW101` |
|---|---:|---:|
| `stop = TRUE` | 0 | 0 |
| Step 0 | 0 | 0 |
| Regulation | Bounded PID demand scaled to 0–1000 | 400 |

Here, **“step 0 drives no output” means no energized valve demand**: both analog commands are explicitly zero, rather than left at their previous values.

**I/O boundary:** StartCommand `%IX100.0`; StopCommand `%IX100.1`; LevelMeter `%IW100`; FillValve `%QW100`; DischargeValve `%QW101`.
