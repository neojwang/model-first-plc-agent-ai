The model below treats the **PLC level-control application** as the system boundary. **A0** is the context function; **A1–A5** are its child functions. Inputs are information transformed by a function; controls are conditions and rules governing its execution; mechanisms are the resources performing it.

The required identifiers `start`, `stop`, `settled`, `r`, `fill_valve`, and `discharge_valve` are preserved. In particular, `fill_valve` and `discharge_valve` are **Boolean activity indications**, not the analog output-register values.

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control tank level** | StartCommand sample (%IX100.0); StopCommand sample (%IX100.1); LevelMeter sample (%IW100) | Start-event rule; initial-step and stop-priority rules; level target \(h_{sp}=h_{target}=0.8h_{span}\); overfill limit \(h_{max}=0.9h_{span}\); tolerance \(\varepsilon=0.02h_{span}\); hold time \(t_h=10\,s\); PID gains \(K_p,T_i,T_d\); PID saturation and integration-suspension rules; discharge opening of 40%; FULL_SCALE = 1000; I/O mapping and driver scaling | FillValve command (%QW100); DischargeValve command (%QW101); `fill_valve`; `discharge_valve` | OpenPLC Runtime; PLC program and scan clock; Modbus TCP connection; Factory I/O analog Level Control scene and driver |
| **A1** | **Interpret command and level samples** | StartCommand sample; StopCommand sample; LevelMeter sample | Rising-edge definition of `start`; level-scaling relationship \(h/h_{span}=\text{LevelMeter}/\text{FULL_SCALE}\); FULL_SCALE = 1000; I/O mapping | `start`; `stop`; measured level \(h\) | PLC input interface; edge-detection logic and previous-sample memory; scaling logic |
| **A2** | **Evaluate level and settling conditions** | Measured level \(h\) | Target \(h_{sp}=h_{target}\); limit \(h_{max}\); tolerance \(\varepsilon\); hold time \(t_h\); regulation-state information; continuous-in-band timing rule | Level error \(e=h_{sp}-h\); `r`; `settled` | Comparison and arithmetic logic; PLC scan clock; hold timer |
| **A3** | **Supervise regulation sequence** | — | `start`; `stop`; `settled`; `r`; initial step 0; stop priority; start and termination rules | Regulation-state information; `fill_valve`; `discharge_valve` | Sequence logic; step-state memory; OpenPLC Runtime |
| **A4** | **Calculate bounded PID demand** | Level error \(e\) | `fill_valve`; PID gains \(K_p,T_i,T_d\); execution interval; output limits of 0–100%; integration suspension during output clamping | Bounded fill-opening demand | PID calculation logic; PID state memory; PLC scan clock |
| **A5** | **Generate analog valve commands** | Bounded fill-opening demand | `fill_valve`; `discharge_valve`; FULL_SCALE = 1000; discharge opening of 40%; zero-output rule for inactive valves; output-register mapping | FillValve command (%QW100); DischargeValve command (%QW101) | Analog-command conversion logic; PLC output interface; Modbus TCP connection; Factory I/O driver |

### Functional interpretation

- **A1:** `start` is TRUE only for the scan detecting a rising edge of StartCommand. `stop` reflects the current StopCommand value.
- **A2:**  
  - `r = LOW` when \(h<h_{target}\).  
  - `r = MID` when \(h_{target}\le h<h_{max}\).  
  - `r = HIGH` when \(h\ge h_{max}\).  
  - `settled` becomes TRUE only after \(|e|\le\varepsilon\) has remained continuously true for 10 seconds during regulation. An out-of-band condition or inactive regulation clears the settling interval.
- **A3:** Step 0 is initially active, with both activity indications FALSE. `start` enables regulation unless `stop` is TRUE. During regulation, both activity indications are TRUE. `stop`, `settled`, or `r = HIGH` returns the sequence to step 0; `stop` has unconditional priority.
- **A4:** While enabled, the PID produces a demand limited to 0–100%, with integration suspended whenever its output is clamped.
- **A5:** While `fill_valve` is TRUE, FillValve receives the bounded demand scaled to 0–1000. While `discharge_valve` is TRUE, DischargeValve receives **400**. Otherwise, the respective output is **0**. Thus step 0 has no valve actuation, including after a stop or regulation termination.

The internal arrows connect A1 to A2/A3, A2 to A3/A4, A3 to A2/A4/A5, and A4 to A5. The Boolean activity indications also appear at the A0 boundary, consistently with the specified output vocabulary.
