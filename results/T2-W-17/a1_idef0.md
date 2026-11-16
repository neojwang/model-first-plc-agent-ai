## A0 context: Control timed tank filling

**Scope:** Control the customized Factory I/O Scene 3 tank using OpenPLC. Fill to a time limit, terminate filling early on high-high level, and give Stop unconditional priority.

In the tables below, signal identifiers denote arrows; other arrow labels are noun phrases. Child functions A1–A4 decompose A0. Their numbering identifies functions, not a mandatory execution order.

### Context ICOM

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| A0 | Control timed tank filling | Operator command signals (`StartCommand`, `StopCommand`); level switch signals (`LSH`, `LSHH`) | `TimerDuration`; initial-step rule; start-event rule; stop-priority rule; timer-or-high-high termination rule; discharge-inhibition rule; I/O mapping specification | Fill-valve command (`fill_valve`); discharge-valve command (`discharge_valve`) | OpenPLC Runtime; PLC scan cycle and memory; timer facility; Modbus TCP connection; Factory I/O tank scene, level switches, and valves |

### A0 decomposition

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| A1 | Acquire commands and level indications | Operator command signals (`StartCommand`, `StopCommand`); level switch signals (`LSH`, `LSHH`) | I/O mapping specification; start-event rule | `start`; `stop`; `LSH`; `LSHH` | OpenPLC input image; Modbus TCP connection; rising-edge detector and previous-command memory |
| A2 | Determine the filling step | `start`; `stop`; `LSHH`; `timer_done` | Initial-step rule; stop-priority rule; timer-or-high-high termination rule; step-transition specification | Filling-step status | OpenPLC execution engine; step-state memory |
| A3 | Measure the filling duration | Filling-step status | `TimerDuration`; timer-start rule; timer-reset rule | `timer_done` | OpenPLC timer facility; PLC time base; timer-state memory |
| A4 | Generate valve commands | Filling-step status; `stop` | Stop-priority rule; initial-step output rule; discharge-inhibition rule; I/O mapping specification | `fill_valve`; `discharge_valve` | OpenPLC output image; Modbus TCP connection; Factory I/O valve actuators |

### Internal arrow connections

- **A1 → A2:** `start`, `stop`, `LSHH`
- **A1 → A4:** `stop`
- **A2 → A3, A4:** Filling-step status
- **A3 → A2:** `timer_done`
- **A4 → A0 boundary:** `fill_valve`, `discharge_valve`
- **A1 → A0 boundary, not used by the control sequence:** `LSH`

`LSH` is acquired but has no specified control effect. In particular, it does **not** terminate filling at 2.4 m.

## Behavioral controls

These rules define the controls referenced in the ICOM tables; they are not PLC code.

| Control | Definition |
|---|---|
| Initial-step rule | Step 0 is the initial and idle step. The other step is the filling step. |
| Start-event rule | `start` is TRUE only for the scan containing the detected rising edge of `StartCommand`. A continuously held button does not generate repeated starts. |
| Stop-priority rule | Whenever `stop` is TRUE, the selected step is step 0 and both outputs are FALSE, regardless of other conditions. |
| Step-transition specification | In step 0, `start` initiates the filling step when `stop` and `LSHH` are FALSE. In the filling step, `timer_done` or `LSHH` returns the sequence to step 0. Otherwise, the current step is retained. |
| Timer-start rule | The timer starts upon entry to the filling step and measures `TimerDuration`. |
| Timer-reset rule | Outside the filling step, elapsed time is reset and `timer_done` is FALSE. Each filling cycle therefore receives a fresh timing interval. |
| Timer-or-high-high termination rule | `timer_done` or `LSHH`, whichever occurs first, ends filling. An already-active `LSHH` prevents opening the valve on a new start. |
| Initial-step output rule | In step 0, `fill_valve` and `discharge_valve` are FALSE. In the filling step, `fill_valve` is TRUE unless Stop forces it FALSE. |
| Discharge-inhibition rule | `discharge_valve` is always FALSE. |

The step determination and output generation must ensure that a detected Stop, elapsed timer, or high-high condition closes the fill valve in the corresponding control scan, rather than leaving it open for an additional scan.

## I/O mapping specification

| Model identifier or boundary signal | OpenPLC tag / parameter | Address | Meaning |
|---|---|---|---|
| Source of `start` | `StartCommand` | `%IX100.0` | Start-button signal; rising edge produces `start` |
| `stop` | `StopCommand` | `%IX100.1` | TRUE requests unconditional stop |
| `LSH` | `LSH` | `%IX100.2` | TRUE indicates liquid at 2.4 m; unused for transitions |
| `LSHH` | `LSHH` | `%IX100.3` | TRUE indicates liquid at the 2.7 m overfill limit |
| `fill_valve` | `FillValve` | `%QX100.0` | TRUE opens the fill valve |
| `discharge_valve` | `DischargeValve` | `%QX100.1` | Held FALSE |
| Timing parameter | `TimerDuration : TIME` | Not specified | Duration of the filling-step timer |

Factory I/O operates as the Modbus TCP slave device; its scene tags must be mapped to these addresses in the driver.
