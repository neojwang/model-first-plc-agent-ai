The model below treats the **level-control application** as the system boundary. The simulated tank is the controlled plant, not a function performed by the controller. Following the requested notation, **A0** is the context function, and **A1–A5** are its child functions.

The prescribed identifiers `start`, `stop`, `settled`, `r`, `fill_valve`, and `discharge_valve` are retained exactly. The last two are Boolean activity indicators; the analog actuator commands remain `FillValve` and `DischargeValve`.

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control tank level** | `StartCommand` sample; `StopCommand` sample; `LevelMeter` sample | Start-event semantics; initial-step and stop-priority rules; level-scaling rules; `FULL_SCALE`; `h_span`; `h_sp = h_target`; `h_max`; `eps`; `t_h`; PID gains `Kp`, `Ti`, `Td`; output-limiting and integration-suspension rules; 40% discharge-opening requirement; I/O mapping | `FillValve` command; `DischargeValve` command; `fill_valve` activity indicator; `discharge_valve` activity indicator | OpenPLC Runtime; PLC program and scan clock; Modbus TCP connection; Factory I/O driver and scene I/O |
| **A1** | **Interpret commands and level measurement** | `StartCommand` sample; `StopCommand` sample; `LevelMeter` sample | Rising-edge rule for `start`; direct Boolean interpretation of `stop`; level-scaling rule; `FULL_SCALE`; `h_span`; region thresholds `h_target` and `h_max`; input-address mapping | `start` event; `stop` condition; measured level `h`; level region `r` | Input acquisition logic; rising-edge detector and previous-command memory; scaling and comparison logic |
| **A2** | **Evaluate level error and settling condition** | Measured level `h` | Set point `h_sp`; tolerance `eps`; hold time `t_h`; regulation activity `fill_valve`; continuous in-band timing rule | Level error `e`; settling condition `settled` | Arithmetic and absolute-value logic; continuous-duration timer; PLC scan clock |
| **A3** | **Manage regulation sequence** | — | `start` event; `stop` condition; settling condition `settled`; level region `r`; initial step 0; transition rules; stop-priority rule | Sequence state; `fill_valve` activity indicator; `discharge_valve` activity indicator | Sequence logic; step-state memory; OpenPLC execution engine |
| **A4** | **Calculate bounded PID fill demand** | Level error `e` | Regulation activity `fill_valve`; PID gains `Kp`, `Ti`, `Td`; calculation interval; 0–100% output bounds; integration-suspension rule during output clamping | Bounded PID fill demand | PID calculation logic; integral and derivative state memory; PLC scan clock |
| **A5** | **Apply valve commands** | Bounded PID fill demand | `fill_valve` activity indicator; `discharge_valve` activity indicator; `stop` condition; zero-output rule for step 0; 40% discharge-opening requirement; `FULL_SCALE`; output-address mapping | `FillValve` command at `%QW100`; `DischargeValve` command at `%QW101` | Output selection and scaling logic; OpenPLC output image; Modbus TCP connection; Factory I/O driver |

### Arrow and behavior definitions

- **Measurement scaling:**  
  \(h=(\texttt{LevelMeter}/1000)\,h_{\text{span}}\). Thus the set point, overfill limit, and tolerance correspond to **800**, **900**, and **20** register units, respectively.

- **A1 command and region outputs:**
  - `start` is TRUE only for the scan containing the rising edge of `StartCommand`.
  - `stop` follows `StopCommand`.
  - `r = LOW` for \(h<h_{\text{target}}\); `r = MID` for \(h_{\text{target}}\le h<h_{\max}\); `r = HIGH` for \(h\ge h_{\max}\).

- **A2 settling evaluation:**  
  \(e=h_{\text{sp}}-h\). `settled` becomes TRUE after \(|e|\le eps\) has remained continuously true for 10 seconds during regulation. The continuous-duration timing is cleared when the level leaves the band or regulation is inactive.

- **A3 sequence behavior:**  
  Step 0 is the initial, inactive state. A `start` event initiates regulation unless `stop` is TRUE. During regulation, both `fill_valve` and `discharge_valve` are TRUE. `settled`, `r = HIGH`, or `stop` ends regulation and returns the sequence to step 0. `stop` has priority.

- **A4–A5 actuator behavior:**  
  The PID demand is limited to 0–100%, with integration suspended while the demand is clamped. While regulation is active, `FillValve` receives the scaled PID demand and `DischargeValve` receives **400**. In step 0, or whenever `stop` is TRUE, both analog commands are **0**. Thus, “step 0 drives no output” is represented as zero valve commands, not retention of the previous commands.

In IDEF0 terms, commands are **inputs to A1** because A1 transforms their raw samples into interpreted signals. Those interpreted signals become **controls of A3**, because they govern sequence execution.
