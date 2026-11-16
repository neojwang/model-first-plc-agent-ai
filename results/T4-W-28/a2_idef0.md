The model below uses a **controller boundary**: the controller receives button states and the measured level and produces analog valve commands. The simulated tank is the external process being controlled. **A0** is the context function; **A1–A5** are its child functions. The decomposition describes functional dependencies, not a mandatory PLC execution order.

The prescribed names `start`, `stop`, `settled`, `r`, `fill_valve`, and `discharge_valve` are retained exactly. In particular, `fill_valve` and `discharge_valve` are **Boolean operating enables**, distinct from the analog commands written to `FillValve` and `DischargeValve`.

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Regulate tank level** | StartCommand state (%IX100.0); StopCommand state (%IX100.1); LevelMeter value (%IW100) | I/O mapping and scaling specification; FULL_SCALE = 1000; measuring span h_span; h_sp = h_target = 0.8 h_span; h_max = 0.9 h_span; eps = 0.02 h_span; t_h = 10 s; PID gains Kp, Ti, Td; initial-step and transition rules; stop priority; PID saturation and integration-suspension rules; discharge-opening requirement | FillValve command (%QW100); DischargeValve command (%QW101) | OpenPLC Runtime; PLC program, memory, and scan clock; Modbus TCP connection to the Factory I/O slave device |
| **A1** | **Acquire and interpret process signals** | StartCommand state; StopCommand state; LevelMeter value | I/O mapping; FULL_SCALE and h_span; rising-edge definition of `start`; level-scaling rule | `start`; `stop`; measured level h | OpenPLC input image; input-processing logic; previous-button-state memory; Modbus TCP interface |
| **A2** | **Evaluate level and settling conditions** | Measured level h | h_sp; h_target; h_max; eps; t_h; `fill_valve` as the regulation-active indication; settling-timer reset rules | Level error e; `r`; `settled` | PLC arithmetic and comparison logic; on-delay timer; scan clock |
| **A3** | **Manage regulation state** | `start`; `stop`; `settled`; `r` | Initial state: step 0; start-transition rule; completion rule; stop priority; state-retention rules | `fill_valve`; `discharge_valve` | PLC state-transition logic; step-state memory |
| **A4** | **Calculate bounded fill demand** | Level error e | `fill_valve`; Kp, Ti, Td; controller update interval; demand limits of 0–100%; integration suspension while clamped | Bounded PID demand | PID computation logic; integral and derivative state memory; scan clock |
| **A5** | **Issue valve commands** | Bounded PID demand | `fill_valve`; `discharge_valve`; FULL_SCALE = 1000; discharge opening of 40%; zero-output rule when disabled; output-register mapping | FillValve command (%QW100); DischargeValve command (%QW101) | OpenPLC output image; integer conversion logic; Modbus TCP interface |

### Functional definitions and interconnections

- **A1 — signal interpretation**
  - `start` is TRUE only for the scan detecting a press of StartCommand, not continuously while the button is held.
  - `stop` follows StopCommand.
  - \(h=(\text{LevelMeter}/1000)\,h_{\text{span}}\).

- **A2 — condition evaluation**
  - \(e=h_{sp}-h\).
  - `r` = LOW when \(h<h_{\text{target}}\), MID when \(h_{\text{target}}\le h<h_{\max}\), and HIGH when \(h\ge h_{\max}\).
  - `settled` becomes TRUE after \(|e|\le eps\) has remained continuously true for 10 s **during regulation**. The timer resets when the band condition fails or regulation is inactive.

- **A3 — state management**
  - Initially, step 0 sets both enables FALSE.
  - `stop` has highest priority: return to step 0 and set both enables FALSE.
  - In step 0, `start` initiates regulation, subject to the stop and high-level protections.
  - During regulation, both enables are TRUE until `settled` is TRUE or `r` is HIGH; then both become FALSE and the controller returns to step 0.
  - A continuously held StartCommand does not restart regulation; a new press is required.

- **A4 — PID demand**
  - Compute the PID demand from e, clamp it to 0–100%, and suspend integral accumulation while clamped.
  - Inactive regulation cannot produce an effective valve command; no particular inactive PID-state reset strategy is specified by the task.

- **A5 — output conversion**
  - If `fill_valve` is TRUE, the FillValve command is the bounded PID percentage scaled to 0–1000; otherwise it is 0.
  - If `discharge_valve` is TRUE, the DischargeValve command is 400; otherwise it is 0.
  - Thus step 0, completion, overfill protection, and `stop` all produce zero commands to both valves.
