The model below treats **A0** as the context function and **A1–A5** as its decomposition. Inputs are transformed data; controls govern when and how a function operates; outputs are produced information or commands; mechanisms are the resources that perform the function.

The required identifiers **start**, **stop**, **settled**, **r**, **fill_valve**, and **discharge_valve** retain their specified meanings. In particular, the two Boolean valve identifiers denote operating modes, **not** analog valve-opening values.

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control tank level** | Level measurement (`LevelMeter`, `%IW100`) | **start**: one-scan event derived from `StartCommand` (`%IX100.0`); **stop**: state of `StopCommand` (`%IX100.1`); level target `h_sp = h_target = 0.8 h_span`; overfill limit `h_max = 0.9 h_span`; tolerance `eps = 0.02 h_span`; hold time `t_h = 10 s`; PID gains `Kp`, `Ti`, `Td`; measurement span `h_span = 10 V`; `FULL_SCALE = 1000`; discharge opening requirement of 40%; initialization, termination, output-limiting, and integration-suspension requirements | Fill-valve command (`FillValve`, `%QW100`); discharge-valve command (`DischargeValve`, `%QW101`); **fill_valve**; **discharge_valve** | OpenPLC Runtime; Factory I/O analog Level Control scene; Modbus TCP connection and mapped I/O; scan clock; start-event detector |
| **A1** | **Interpret level measurement** | Level measurement (`LevelMeter`) | `FULL_SCALE`; `h_span`; `h_sp`; `h_target`; `h_max`; measurement-scaling rule | Scaled level `h`; level error `e`; level region **r** | OpenPLC arithmetic and comparison operations |
| **A2** | **Evaluate sustained settling** | Level error `e` | Regulation-active state; `eps`; `t_h`; timer-reset requirement outside regulation or outside the tolerance band | Settling indication **settled** | OpenPLC on-delay timer; scan clock |
| **A3** | **Supervise regulation sequence** | — | **start**; **stop**; **settled**; **r**; initial-step requirement; stop-priority requirement; regulation-entry and termination rules | Sequence state; regulation-active state | OpenPLC sequence/state logic; state memory |
| **A4** | **Calculate bounded PID demand** | Level error `e` | Regulation-active state; `Kp`, `Ti`, `Td`; scan interval; PID output bounds of 0–100%; integration-suspension requirement during output clamping | Bounded fill-opening demand | OpenPLC PID calculation; PID state memory; output limiter; integration-inhibition logic |
| **A5** | **Apply valve commands** | Bounded fill-opening demand | Regulation-active state; **stop**; `FULL_SCALE`; discharge opening requirement of 40%; zero-output requirement in step 0 and on termination or stop | Fill-valve command (`FillValve`, `%QW100`); discharge-valve command (`DischargeValve`, `%QW101`); **fill_valve**; **discharge_valve** | OpenPLC output assignment and analog scaling; Modbus TCP output mapping; Factory I/O valve interfaces |

### Functional interpretation

- **A1 — Scaling and classification**
  - `h = (LevelMeter / FULL_SCALE) × h_span`
  - `e = h_sp − h`
  - **r** = `LOW` for `h < h_target`, `MID` for `h_target ≤ h < h_max`, and `HIGH` for `h ≥ h_max`.

- **A2 — Continuous hold condition**  
  **settled** becomes TRUE only after `|e| ≤ eps` has remained continuously true for 10 seconds during regulation. Leaving the band or leaving regulation resets the timing condition.

- **A3 — Sequence and priority**  
  Initialization selects step 0. **stop** has highest priority and forces step 0. During regulation, **settled** or **r** = `HIGH` terminates regulation. In step 0, **start** requests regulation; an already-high level must not produce an active valve command.

- **A4 — PID constraint**  
  The fill demand is limited to 0–100%, with integration suspended while the PID output is clamped.

- **A5 — Output interpretation**  
  During regulation, **fill_valve** and **discharge_valve** are TRUE, `FillValve` is the bounded PID demand scaled to `0…1000`, and `DischargeValve = 400`. Otherwise, both Boolean outputs are FALSE and both analog commands are zero. A zero PID demand does **not** by itself make **fill_valve** FALSE: that identifier indicates that PID control is active.

Here, “step 0 drives no output” is interpreted consistently with the explicit shutdown requirements: **both analog output commands are held at zero**, rather than left at their previous values.
