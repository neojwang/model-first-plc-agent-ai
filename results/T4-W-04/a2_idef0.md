The model below treats the controller as the system boundary: it receives plant measurements and operator commands and produces valve commands. The tank is the controlled plant, not a child function of the controller.

**A0** is the context function requested; **A1–A5** are its functional decomposition. In strict IDEF0 diagram notation, the context diagram is **A-0**, containing the A0 function, and its decomposition diagram is **A0**.

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control tank level** | LevelMeter measurement (%IW100) | StartCommand (%IX100.0); StopCommand (%IX100.1); FULL_SCALE = 1000; measuring span h_span; h_sp = h_target = 0.8 h_span; h_max = 0.9 h_span; eps = 0.02 h_span; t_h = 10 s; PID gains Kp, Ti, Td; initial-step rule; stopping rules; output limits; integration-suspension rule; discharge-opening requirement | FillValve command (%QW100); DischargeValve command (%QW101) | OpenPLC Runtime; PLC scan execution and timebase; controller state memory; Modbus TCP connection; Factory I/O analog I/O interface |
| **A1** | **Interpret commands and level measurement** | LevelMeter measurement | StartCommand; StopCommand; FULL_SCALE; h_span; h_sp; h_target; h_max; rising-edge detection rule; level-region definitions | `start`; `stop`; measured level h; level error e; level region `r` | PLC arithmetic and comparison operations; previous-command memory; Modbus input interface |
| **A2** | **Manage regulation sequence** | — | `start`; `stop`; `settled`; `r`; initial step 0; start-transition rule; completion-transition rule; stop priority | Sequence state; `fill_valve`; `discharge_valve` | PLC sequence logic; sequence-state memory |
| **A3** | **Compute bounded PID demand** | Level error e | `fill_valve`; Kp, Ti, Td; scan interval; 0–100% output limits; integration-suspension rule during clamping | Bounded fill-opening demand | PLC PID algorithm; integrator and derivative-state memory; PLC timebase |
| **A4** | **Qualify level settling** | Level error e | Sequence state; eps; t_h; continuous-in-band timing rule; timer reset rule outside regulation or outside the tolerance band | `settled` | PLC on-delay timing logic; timer memory; PLC timebase |
| **A5** | **Generate valve commands** | Bounded fill-opening demand | `fill_valve`; `discharge_valve`; `stop`; FULL_SCALE; 40% discharge-opening requirement; zero-output rule for step 0 and stopping | FillValve command (%QW100); DischargeValve command (%QW101) | PLC output scaling and integer conversion; output registers; Modbus output interface |

### Arrow semantics and functional rules

- **A1 — measurement and command interpretation**
  - `start` is TRUE only for the scan detecting a rising edge of StartCommand.
  - `stop` follows StopCommand.
  - \(h = (\text{LevelMeter}/\text{FULL_SCALE})\,h_{\text{span}}\).
  - \(e = h_{sp}-h\).
  - `r` is **LOW** for \(h<h_{target}\), **MID** for \(h_{target}\le h<h_{max}\), and **HIGH** for \(h\ge h_{max}\).

- **A2 — sequence management**
  - Step 0 is the initial, inactive step; both `fill_valve` and `discharge_valve` are FALSE.
  - `start` initiates regulation, subject to the stop and high-level conditions.
  - During regulation, both `fill_valve` and `discharge_valve` are TRUE.
  - `settled` or `r = HIGH` ends regulation and returns the sequence to step 0.
  - `stop` takes priority over starting or continuing regulation.

- **A3–A4 — regulation and completion**
  - The PID demand is clamped to 0–100%; integration is suspended while the output is clamped.
  - `settled` becomes TRUE only after \(|e|\le eps\) has remained continuously true for 10 s during regulation. Leaving the band or leaving regulation resets the qualification timer.

- **A5 — output realization**
  - When `fill_valve` is TRUE, FillValve receives the bounded PID demand scaled to **0–1000**.
  - When `discharge_valve` is TRUE, DischargeValve receives **400**.
  - In step 0, on completion, or whenever `stop` is TRUE, both physical output commands are **0**. Thus, “step 0 drives no output” is implemented as zero commands, not as retention of previous register values.

The lowercase identifiers `fill_valve` and `discharge_valve` are Boolean activity signals; the capitalized FillValve and DischargeValve names denote the analog output registers.
