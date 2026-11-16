**Scope:** the model covers the PLC level-control application, not the tank’s physical dynamics. **A0** is the context function; **A1–A5** are its immediate child functions. Arrow names are noun phrases; function names are verb phrases.

The required identifiers `start`, `stop`, `settled`, `r`, `fill_valve`, and `discharge_valve` retain their specified meanings. In particular, `fill_valve` and `discharge_valve` are Boolean operating indications, distinct from the analog output commands `FillValve` and `DischargeValve`.

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control tank level** | StartCommand signal (`%IX100.0`); StopCommand signal (`%IX100.1`); LevelMeter reading (`%IW100`) | I/O mapping and scaling specification; `FULL_SCALE = 1000`; measuring span `h_span`; target `h_sp = h_target = 0.8 h_span`; overfill limit `h_max = 0.9 h_span`; tolerance `eps = 0.02 h_span`; hold time `t_h = 10 s`; PID gains `Kp`, `Ti`, `Td`; initial-step, operating, termination, and stop-priority rules | FillValve command (`%QW100`); DischargeValve command (`%QW101`); `fill_valve`; `discharge_valve` | OpenPLC Runtime; PLC application and execution clock; Modbus TCP connection and Factory I/O driver |
| **A1** | **Interpret commands and calculate level error** | StartCommand signal; StopCommand signal; LevelMeter reading | I/O mapping; `FULL_SCALE`; `h_span`; `h_sp`; rising-edge definition of `start` | `start`; `stop`; measured level `h`; level error `e` | PLC input processing, scaling, arithmetic, and edge-detection logic; command-history memory |
| **A2** | **Evaluate level region and settling condition** | Measured level `h`; level error `e` | `h_target`; `h_max`; `eps`; `t_h`; regulation-state indication; continuous-band timing and timer-reset rules | `r`; `settled` | PLC comparison logic; scan clock and hold timer |
| **A3** | **Supervise regulation state** | Current regulation-state indication | `start`; `stop`; `settled`; `r`; initial-step rule; stop-priority rule; start and termination rules | Updated regulation-state indication; `fill_valve`; `discharge_valve` | PLC sequence logic and state memory |
| **A4** | **Calculate bounded PID demand** | Level error `e` | `fill_valve`; `Kp`, `Ti`, `Td`; execution interval; output limits of 0–100%; integration-suspension rule during output clamping | Bounded fill demand | PLC PID calculation; integral and derivative state memory; execution clock |
| **A5** | **Apply valve commands** | Bounded fill demand | `fill_valve`; `discharge_valve`; `FULL_SCALE`; fixed discharge opening of 40%; inactive-output and stop-zeroing rules; output address mapping | FillValve command (`%QW100`); DischargeValve command (`%QW101`) | PLC output scaling and register-writing logic; Modbus TCP connection and Factory I/O driver |

### Behavioral meaning of the arrows

- **A1:**  
  `start` is TRUE only on the scan detecting a press of StartCommand; `stop` follows StopCommand.  
  \[
  h=\frac{\text{LevelMeter}}{\text{FULL\_SCALE}}h_{\text{span}},
  \qquad e=h_{sp}-h.
  \]

- **A2:**  
  `r = LOW` for \(h<h_{target}\); `r = MID` for \(h_{target}\le h<h_{max}\); and `r = HIGH` for \(h\ge h_{max}\).  
  `settled` becomes TRUE only after \(|e|\le eps\) has remained continuously true for 10 seconds during regulation. The hold timer resets when the level leaves the band or regulation is inactive.

- **A3:**  
  Step 0 is the initial, inactive state. With `stop = FALSE`, `start` initiates regulation. During regulation, both `fill_valve` and `discharge_valve` are TRUE. `settled` or `r = HIGH` ends regulation and returns the controller to step 0. `stop = TRUE` overrides other conditions and returns the controller to step 0 with both indications FALSE.

- **A4–A5:**  
  While enabled, the PID demand is clamped to 0–100%, with integration suspended while clamped. The fill command is the bounded demand scaled to 0–1000; the discharge command is 400. In step 0, including after stopping or completing regulation, both analog commands are zero.
