## A0 context model — Control timed tank filling

**Purpose:** Fill the tank for at most `TimerDuration`, terminating filling immediately on `LSHH` or `stop`.

**Boundary:** The model covers PLC sequence control, timer operation, and valve commands. The tank, switches, valves, and Modbus connection provide the physical/simulated execution mechanisms.

The child functions are:

- **A1 — Manage filling steps**
- **A2 — Measure filling time**
- **A3 — Generate valve commands**

All function names are verb phrases. Signal identifiers and internal arrow names below are noun phrases.

## ICOM table

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control timed tank filling** | `start`; `stop`; `LSHH` | `TimerDuration`; initial-step rule; start-event rule; stop-priority rule; timer-or-high-high termination rule; discharge-inhibition rule | `fill_valve`; `discharge_valve` | OpenPLC Runtime; Factory I/O digital tank scene; Modbus TCP interface; capacitive level switches; valve actuators |
| **A1** | **Manage filling steps** | `start`; `stop`; `LSHH`; `timer_done` | Initial-step rule; start-event rule; stop-priority rule; timer-or-high-high termination rule | Filling-step state | OpenPLC Runtime; sequence-state memory |
| **A2** | **Measure filling time** | Filling-step state | `TimerDuration`; timer-enable rule; timer-reset rule | `timer_done` | OpenPLC Runtime; timer function block; PLC time base |
| **A3** | **Generate valve commands** | Filling-step state; `stop`; `LSHH`; `timer_done` | Initial-step rule; stop-priority rule; timer-or-high-high termination rule; discharge-inhibition rule | `fill_valve`; `discharge_valve` | OpenPLC Runtime; output image; Modbus TCP interface; valve actuators |

**Unused interface:** `LSH` is available from the plant but is not used by this task. It is therefore documented in the interface mapping below, rather than drawn as a functional arrow with an invented purpose. In particular, reaching 2.4 m does **not** terminate filling.

## Arrow connections and boundary balancing

| Arrow | Source | Destination | Meaning |
|---|---|---|---|
| `start` | A0 input boundary | A1 | One-scan event representing a new Start button press |
| `stop` | A0 input boundary | A1, A3 | Stop request with overriding priority |
| `LSHH` | A0 input boundary | A1, A3 | Liquid detection at the 2.7 m overfill limit |
| `TimerDuration` | A0 control boundary | A2 | Configured filling-time limit |
| Filling-step state | A1 | A2, A3 | Current step: step 0 or filling step |
| `timer_done` | A2 | A1, A3 | Completion indication for the filling-step timer |
| `fill_valve` | A3 | A0 output boundary | Fill-valve command |
| `discharge_valve` | A3 | A0 output boundary | Discharge-valve command, always FALSE |

The behavioral-rule controls listed at A0 are inherited by the indicated child functions. `timer_done` and Filling-step state are internal arrows, not additional plant I/O.

## Behavioral controls

| Control | Required interpretation |
|---|---|
| Initial-step rule | Initialization selects step 0. Step 0 commands both outputs FALSE. |
| Start-event rule | In step 0, `start` selects the filling step only when neither `stop` nor `LSHH` is TRUE. A held Start button does not repeatedly start new cycles. |
| Stop-priority rule | Whenever `stop` is TRUE, select step 0 and command both outputs FALSE, regardless of other conditions. |
| Timer-or-high-high termination rule | During filling, either `timer_done` or `LSHH` selects step 0 and closes the fill valve. `LSHH` also inhibits opening when already TRUE. |
| Timer-enable rule | Entry into the filling step enables timing and opens the fill valve in the same control cycle, subject to the overriding termination conditions. |
| Timer-reset rule | Step 0 disables and resets the filling timer. A new filling cycle starts with a fresh elapsed time. |
| Discharge-inhibition rule | `discharge_valve` remains FALSE in every step and under every condition. |

The A1–A2 feedback represents cyclic PLC execution, not an instruction execution order. The implementation must ensure that a stale `timer_done` indication cannot terminate a newly started cycle.

## Plant interface mapping

| Identifier | Scene/runtime mapping | Interpretation |
|---|---|---|
| `start` | Rising-edge event derived from `StartCommand AT %IX100.0` | TRUE only in the scan of a new press |
| `stop` | `StopCommand AT %IX100.1` | Level-sensitive stop request |
| `LSH` | `LSH AT %IX100.2` | Liquid detected at 2.4 m; unused by this control task |
| `LSHH` | `LSHH AT %IX100.3` | Liquid detected at 2.7 m |
| `timer_done` | Internal filling-timer completion indication | Not a Modbus input |
| `fill_valve` | `FillValve AT %QX100.0` | TRUE opens the fill valve |
| `discharge_valve` | `DischargeValve AT %QX100.1` | Always FALSE |
| `TimerDuration` | PLC parameter of type `TIME` | Filling-time preset |

**Configuration assumption:** `TimerDuration` is a valid, nonnegative timer preset; parameter validation and fault recovery are outside the stated task.
