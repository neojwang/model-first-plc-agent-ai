The model below treats the **controller** as the system boundary; the Factory I/O tank is the external plant. In IDEF0 terminology, the context diagram is **A-0**, containing function **A0**; its decomposition contains **A1–A5**.

`fill_valve` and `discharge_valve` are the specified Boolean operating indications, **not** the analog valve commands. `start`, `stop`, `settled`, and `r` retain exactly the specified meanings.

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control tank level** | StartCommand signal (%IX100.0); StopCommand signal (%IX100.1); LevelMeter reading (%IW100) | I/O mapping; FULL_SCALE = 1000; measuring span h_span; target h_sp = h_target = 0.8 h_span; overfill limit h_max = 0.9 h_span; tolerance eps = 0.02 h_span; hold time t_h = 10 s; PID gains Kp, Ti, Td; start-event rule; stop priority; initial-step and termination rules; PID saturation and integration-suspension rules; discharge opening of 40% | FillValve command (%QW100); DischargeValve command (%QW101); `fill_valve`; `discharge_valve` | OpenPLC Runtime; PLC program and state memory; PID and timer facilities; Modbus TCP communication facilities; Factory I/O driver |
| **A1** | **Interpret commands and level measurements** | StartCommand signal; StopCommand signal; LevelMeter reading | I/O mapping; FULL_SCALE; h_span; h_sp = h_target; h_max; rising-edge definition of `start`; level-region definitions | `start`; `stop`; measured level h; level error e; `r` | PLC input processing; edge-detection logic and previous-input memory; scaling and comparison logic |
| **A2** | **Verify sustained level tolerance** | Level error e | Regulation state from A3; eps; t_h; continuous in-band timing rule; timer reset when the error leaves the band or regulation is inactive | `settled` | PLC timer; tolerance-comparison logic; timer state memory |
| **A3** | **Manage regulation state** | — | `start`; `stop`; `settled`; `r`; initial step 0; stop priority; transition rules: step 0 → regulation on `start`, regulation → step 0 on `settled` or `r = HIGH`; zero-output requirement in step 0 | Regulation state; `fill_valve`; `discharge_valve` | PLC state-transition logic; step-state memory |
| **A4** | **Calculate bounded PID demand** | Level error e | `fill_valve`; PID gains Kp, Ti, Td; controller time base; output limits of 0–100%; integration suspension while the PID output is clamped | Bounded fill demand | PID algorithm; PID state memory; PLC cyclic execution |
| **A5** | **Issue valve commands** | Bounded fill demand | `fill_valve`; `discharge_valve`; `stop`; FULL_SCALE; output-address mapping; fixed discharge opening of 40%; zero-output requirement when inactive or stopped | FillValve command (%QW100); DischargeValve command (%QW101) | Output scaling and gating logic; OpenPLC output image; Modbus TCP communication facilities; Factory I/O driver |

**Arrow definitions and boundary details**

- **A1 calculations:**  
  \(h=(\text{LevelMeter}/\text{FULL\_SCALE})h_{\text{span}}\), and \(e=h_{\text{sp}}-h\).  
  `start` is TRUE only for the scan detecting a StartCommand press; `stop` follows StopCommand.  
  `r = LOW` for \(h<h_{\text{target}}\), `MID` for \(h_{\text{target}}\le h<h_{\max}\), and `HIGH` for \(h\ge h_{\max}\).

- **A2 timing:** `settled` becomes TRUE only after \(|e|\le\text{eps}\) has remained continuously true for 10 s during regulation.

- **A3 operating indications:** `fill_valve` and `discharge_valve` are TRUE during regulation and FALSE in step 0. `stop` overrides a simultaneous `start` and returns the controller to step 0.

- **A5 command generation:** During regulation, FillValve receives the bounded PID demand scaled to **0–1000**, and DischargeValve receives **400**. In step 0, on `stop`, or after either termination condition, both commands are **0**.

The regulation state, measured level, error, `start`, `stop`, `r`, `settled`, and bounded fill demand are internal decomposition arrows; they need not appear as external outputs of A0.
