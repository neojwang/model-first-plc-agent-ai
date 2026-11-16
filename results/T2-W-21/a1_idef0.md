## A0 context and decomposition

**System boundary:** the PLC control function, including input interpretation, step control, timing, and output generation. The tank, switches, valves, and Factory I/O communication interface are external plant/interface mechanisms.

In the tables, semicolon-separated entries represent separate, named arrows. Function names are verb phrases; arrow names are noun phrases or the required signal identifiers.

### A0 — Control timed tank filling

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| A0 | Control timed tank filling | StartCommand signal; StopCommand signal; LSH signal; LSHH signal | TimerDuration; Initial-step requirement; Start-event requirement; Timer-or-overfill termination rule; Stop-priority rule; Discharge-inhibition rule; I/O address mapping | fill_valve; discharge_valve | OpenPLC Runtime; PLC scan execution; Modbus TCP interface; Factory I/O tank scene |

### A0 child functions

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| A1 | Interpret operator commands and level signals | StartCommand signal; StopCommand signal; LSH signal; LSHH signal | I/O address mapping; Start-event requirement; Active-high signal definitions | start; stop; LSH; LSHH | PLC input image; Rising-edge detection memory; Modbus TCP interface |
| A2 | Select the filling sequence step | start; stop; LSHH; timer_done | Initial-step requirement; Step-transition rules; Stop-priority rule | Sequence step; Filling-step activity | PLC scan execution; Sequence-state memory |
| A3 | Measure the filling interval | Filling-step activity | TimerDuration; Timer-start rule; Timer-reset rule | timer_done | PLC timer facility; Timer-state memory |
| A4 | Command the tank valves | Sequence step | stop; LSHH; timer_done; Step-output rules; Discharge-inhibition rule; I/O address mapping | fill_valve; discharge_valve | PLC output image; Modbus TCP interface; Fill-valve actuator; Discharge-valve actuator |

## Arrow connections and meanings

| Arrow | Source → destination | Meaning |
|---|---|---|
| start | A1 → A2 | Rising-edge event from StartCommand, TRUE only during the scan in which the press is detected |
| stop | A1 → A2, A4 | Current StopCommand condition; TRUE has priority over starting or continuing filling |
| LSH | A1 → observation boundary | Target-level indication at 2.4 m; monitored but not used to terminate filling in this task |
| LSHH | A1 → A2, A4 | Overfill-limit indication at 2.7 m |
| Sequence step | A2 → A4 | Selected state: step 0, idle, or step 1, filling |
| Filling-step activity | A2 → A3 | Indication that the filling interval is active |
| timer_done | A3 → A2, A4 | Indication that the active filling interval has reached TimerDuration |
| fill_valve | A4 → plant | Fill-valve command |
| discharge_valve | A4 → plant | Discharge-valve command, always FALSE |

The **LSH observation boundary** is an explicitly unused monitoring destination, not an additional child function or a valve-control condition.

## Control definitions

- **Initial-step requirement:** initialize the sequence in step 0, with both outputs FALSE.
- **Step-transition rules:**
  - In step 0, `start` permits entry into step 1 only when `stop` and `LSHH` are FALSE.
  - In step 1, `timer_done` or `LSHH` causes return to step 0.
  - A `start` event during step 1 does not restart or extend filling.
- **Stop-priority rule:** whenever `stop` is TRUE, select step 0 and force both outputs FALSE, regardless of other conditions.
- **Timer-start rule:** start a new interval upon entry into step 1.
- **Timer-reset rule:** clear elapsed time and `timer_done` outside step 1; a subsequent filling cycle receives a fresh interval.
- **Step-output rules:** `fill_valve` is TRUE only while step 1 is selected and none of `stop`, `LSHH`, or `timer_done` is TRUE. Otherwise it is FALSE.
- **Discharge-inhibition rule:** `discharge_valve` remains FALSE in every state.

The A2–A3 feedback represents state and timer interaction, **not a mandated extra scan of delay**. Timer expiry, overfill detection, and stop must suppress the fill command in the scan in which they are recognized.

## I/O address mapping

| External tag or command | Address | Model signal |
|---|---|---|
| StartCommand | `%IX100.0` | Source of `start` |
| StopCommand | `%IX100.1` | `stop` |
| LSH | `%IX100.2` | `LSH` |
| LSHH | `%IX100.3` | `LSHH` |
| FillValve | `%QX100.0` | `fill_valve` |
| DischargeValve | `%QX100.1` | `discharge_valve` |

`TimerDuration` is a TIME parameter supplied as a control to the timing function; it is not a mapped digital input.
