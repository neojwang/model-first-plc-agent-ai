The model below treats **A0 as the overall control function** (shown on the IDEF0 context diagram, A-0), decomposed into A1–A5. Arrows between child functions are internal to A0.

The required identifiers `start`, `stop`, `settled`, and `r` are retained for receptivities. The identifiers `fill_valve` and `discharge_valve` denote **Boolean activity signals**, not the analog valve commands.

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control the tank level** | StartCommand signal; StopCommand signal; LevelMeter register value | I/O address map; FULL_SCALE = 1000; measuring span h_span; h_sp = h_target = 0.8 h_span; h_max = 0.9 h_span; eps = 0.02 h_span; t_h = 10 s; PID gains Kp, Ti, Td; initial-step rule; start-event rule; stop-priority rule; regulation and termination rules | FillValve analog command; DischargeValve analog command; `fill_valve` activity signal; `discharge_valve` activity signal | OpenPLC Runtime; Modbus TCP connection; Factory I/O driver and simulated level-control plant |
| **A1** | **Acquire and interpret plant signals** | StartCommand signal at %IX100.0; StopCommand signal at %IX100.1; LevelMeter register value at %IW100 | I/O address map; FULL_SCALE = 1000; measuring span h_span; rising-edge definition of `start` | `start` event; `stop` signal; measured level h | OpenPLC input image; rising-edge detector and previous-input memory; Modbus TCP interface |
| **A2** | **Evaluate level conditions** | Measured level h | h_sp = h_target = 0.8 h_span; h_max = 0.9 h_span; eps = 0.02 h_span; t_h = 10 s; regulation activity from `fill_valve`; continuous-in-band timing rule | Level error e; `r` level-region classification; `settled` condition | OpenPLC arithmetic and comparison operations; hold timer; PLC time base |
| **A3** | **Supervise the regulation sequence** | `start` event; `stop` signal; `settled` condition; `r` level-region classification | Initial step 0; start-triggered regulation rule; stop-priority rule; termination rule (`settled` or `r = HIGH`); step-0 zero-output rule | `fill_valve` activity signal; `discharge_valve` activity signal | OpenPLC sequence logic; step-state memory |
| **A4** | **Compute the bounded PID demand** | Level error e | `fill_valve` activity signal; PID gains Kp, Ti, Td; PLC execution interval; output bounds of 0–100%; integration-suspension rule while the output is clamped | Bounded PID demand | OpenPLC PID implementation; integral and derivative state memory; PLC time base |
| **A5** | **Issue the valve commands** | Bounded PID demand | `fill_valve` activity signal; `discharge_valve` activity signal; FULL_SCALE = 1000; discharge-opening setting of 40%; step-0 and stop zero-output rules; output address map | FillValve analog command at %QW100; DischargeValve analog command at %QW101 | OpenPLC output image; integer conversion and scaling operations; Modbus TCP interface; Factory I/O driver |

### Arrow definitions and functional constraints

- **Signal interpretation — A1**
  - `start` is TRUE only for the scan detecting a rising edge of StartCommand.
  - `stop` follows StopCommand.
  - The measured level is scaled as  
    \[
    h=\frac{\text{LevelMeter}}{1000}\,h_{\text{span}}.
    \]

- **Condition evaluation — A2**
  - \(e=h_{sp}-h\).
  - `r = LOW` for \(h<h_{target}\).
  - `r = MID` for \(h_{target}\le h<h_{max}\).
  - `r = HIGH` for \(h\ge h_{max}\).
  - `settled` becomes TRUE after \(|e|\le eps\) continuously for 10 s during regulation. The hold timer resets when the level leaves the tolerance band or regulation is inactive.

- **Sequence supervision — A3**
  - Step 0 is the initial state; both activity signals are FALSE.
  - `start` initiates regulation; both activity signals are TRUE while regulation remains active.
  - `settled` or `r = HIGH` ends regulation and returns the sequence to step 0.
  - `stop` has overriding priority: while TRUE, the sequence remains in step 0 and both activity signals are FALSE. A simultaneous start cannot override stop or the high-level termination condition.

- **Command generation — A4–A5**
  - During regulation, A4 clamps the PID demand to 0–100% and suspends integral accumulation while clamped.
  - With `fill_valve = TRUE`, FillValve receives the bounded PID demand scaled to 0–1000; otherwise it receives 0.
  - With `discharge_valve = TRUE`, DischargeValve receives \(0.4\times1000=400\); otherwise it receives 0.
  - Stop and termination decisions must affect the commands in the same control scan, without an additional scan of valve actuation.
