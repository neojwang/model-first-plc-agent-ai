The model below treats **A0** as the context function and **A1–A5** as its decomposition. Arrow placement follows IDEF0: **inputs** are transformed, **controls** govern the transformation, **outputs** are produced, and **mechanisms** perform the function.

The identifiers `start`, `stop`, `settled`, `r`, `fill_valve`, and `discharge_valve` retain their specified meanings. In particular, `fill_valve` and `discharge_valve` are Boolean activity signals, **not** the analog valve-opening commands.

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control tank level** | StartCommand signal (%IX100.0); StopCommand signal (%IX100.1); LevelMeter value (%IW100) | I/O mapping; FULL_SCALE = 1000; measuring span h_span; h_sp = h_target = 0.8 h_span; h_max = 0.9 h_span; eps = 0.02 h_span; t_h = 10 s; PID gains Kp, Ti, Td; initial-step rule; stop-priority rule; valve-opening limits; integration-suspension rule; discharge-opening requirement | FillValve command (%QW100); DischargeValve command (%QW101) | OpenPLC Runtime; PLC control program; Modbus TCP connection; Factory I/O driver and analog Level Control scene |
| **A1** | **Acquire and interpret plant signals** | StartCommand signal; StopCommand signal; LevelMeter value | I/O mapping; FULL_SCALE; h_span; rising-edge definition of `start` | `start`; `stop`; measured level h | PLC input image; rising-edge detector with previous-input memory; level-scaling logic; Modbus TCP interface |
| **A2** | **Evaluate level and settling conditions** | Measured level h | h_sp; h_target; h_max; eps; t_h; `fill_valve` as the regulation-active condition; timer-reset rule outside the tolerance band or outside regulation | Level error e; `r`; `settled` | Comparison logic; absolute-value calculation; on-delay timer; PLC scan time base |
| **A3** | **Manage regulation sequence** | `start`; `stop`; `r`; `settled` | Step 0 as the initial state; `stop` priority; start-transition rule; completion rule (`settled` or `r = HIGH`); step-0 zero-output rule | `fill_valve`; `discharge_valve`; sequence state | PLC sequence logic; retained inter-scan state memory |
| **A4** | **Calculate bounded PID demand** | Level error e | Kp; Ti; Td; `fill_valve`; PID execution interval; 0–100% output limits; integration suspension during output clamping | Bounded fill-opening demand | PID calculation logic; integrator and derivative state memory; output limiter; anti-windup logic; PLC time base |
| **A5** | **Generate valve commands** | Bounded fill-opening demand | `fill_valve`; `discharge_valve`; `stop`; FULL_SCALE; 40% discharge-opening requirement; zero-output rule when inactive or stopped; integer-register encoding | FillValve command (%QW100); DischargeValve command (%QW101) | Output-selection and scaling logic; PLC output image; Modbus TCP interface; Factory I/O driver |

### Functional interpretation

- **A1 — Signal interpretation:**  
  \(h=(\text{LevelMeter}/1000)\,h_{\text{span}}\). `start` is a one-scan rising-edge event; `stop` reflects the current StopCommand level.

- **A2 — Conditions:**  
  \(e=h_{sp}-h\). The region `r` is:
  - `LOW` for \(h<h_{\text{target}}\);
  - `MID` for \(h_{\text{target}}\le h<h_{\max}\);
  - `HIGH` for \(h\ge h_{\max}\).

  `settled` becomes TRUE only after \(|e|\le eps\) has remained continuously true for 10 seconds during regulation.

- **A3 — Sequence:**  
  Step 0 sets both activity signals FALSE. A `start` event enters regulation unless `stop` is TRUE. During regulation, both activity signals are TRUE. `settled`, `r = HIGH`, or `stop` returns the sequence to step 0; `stop` has overriding priority.

- **A4 — PID:**  
  The fill-opening demand is clamped to 0–100%. Integration is suspended while the output is clamped. PID demand cannot actuate a valve when regulation is inactive.

- **A5 — Physical outputs:**  
  During regulation, FillValve receives the bounded PID demand scaled to **0–1000**, and DischargeValve receives **400**. In step 0, or whenever `stop` is TRUE, **both commands are 0**.
