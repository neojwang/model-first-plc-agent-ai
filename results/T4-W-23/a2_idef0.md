The model below treats **A0 as the requested context function** and A1–A5 as its child functions. Process measurements and raw button signals are inputs; operating rules, parameters, and interpreted transition conditions are controls. Internal arrows connect the child functions.

The required identifiers **start, stop, settled, r, fill_valve, discharge_valve** are preserved exactly. The Boolean output indicators `fill_valve` and `discharge_valve` are distinct from the analog output registers `FillValve` and `DischargeValve`.

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control tank level** | Level measurement `LevelMeter` (%IW100); start-button signal `StartCommand` (%IX100.0); stop-button signal `StopCommand` (%IX100.1) | Initial-step rule; start-event rule; stop-priority rule; PID regulation rule; output-clamping and integration-suspension rules; termination rule; `FULL_SCALE = 1000`; measuring span `h_span`; target `h_sp = h_target = 0.8 h_span`; overfill limit `h_max = 0.9 h_span`; tolerance `eps = 0.02 h_span`; hold time `t_h = 10 s`; PID gains `Kp`, `Ti`, `Td`; discharge opening of 40% | Fill-valve command `FillValve` (%QW100); discharge-valve command `DischargeValve` (%QW101); regulation indicators `fill_valve`, `discharge_valve` | OpenPLC Runtime and PLC program; Factory I/O tank, level meter, and valves; Modbus TCP interface and Factory I/O driver with Scale = 100 |
| **A1** | **Acquire and interpret signals** | `StartCommand`; `StopCommand`; `LevelMeter`; previous start-button state | Rising-edge definition of `start`; level-scaling relationship; `FULL_SCALE`; `h_span`; `h_sp`; `h_target`; `h_max`; level-region definitions | Start event `start`; stop condition `stop`; measured level `h`; level error `e = h_sp − h`; level region `r`; updated previous start-button state | PLC input acquisition; Modbus TCP interface; edge-detection logic; scaling, arithmetic, and comparison logic |
| **A2** | **Evaluate level settling** | Level error `e`; elapsed in-band time | Regulation-enable status; tolerance `eps`; hold time `t_h`; continuous-hold rule; timer-reset rule when regulation is inactive or the error leaves the tolerance band | Settling condition `settled`; updated elapsed in-band time | PLC cyclic execution; timer or equivalent elapsed-time logic |
| **A3** | **Manage regulation sequence** | Current sequence state | `start`; `stop`; `settled`; `r`; initial state = step 0; transition rules; unconditional stop priority | Updated sequence state; regulation-enable status | PLC sequence/state logic; state memory |
| **A4** | **Calculate bounded PID demand** | Level error `e`; PID controller history | Regulation-enable status; `Kp`, `Ti`, `Td`; controller execution interval; PID output limits of 0–100%; integration suspension while the output is clamped | Bounded PID demand; updated PID controller history | PID calculation logic; controller-state memory; PLC execution clock |
| **A5** | **Command tank valves** | Bounded PID demand | Regulation-enable status; `stop`; `FULL_SCALE = 1000`; discharge opening of 40%; zero-output rule for step 0 and stopping; analog-output scaling rule | Fill-valve command `FillValve` (%QW100); discharge-valve command `DischargeValve` (%QW101); `fill_valve`; `discharge_valve` | PLC output logic; analog output registers; Modbus TCP interface; Factory I/O valve actuators |

### Arrow and behavior definitions

- **`start`** is TRUE only for the scan detecting a press of `StartCommand`; **`stop`** follows the TRUE condition of `StopCommand`.
- **`r`** is:
  - `LOW` when `h < h_target`;
  - `MID` when `h_target <= h < h_max`;
  - `HIGH` when `h >= h_max`.
- **`settled`** becomes TRUE only after `|e| <= eps` has remained continuously true for 10 seconds during regulation.
- **A3 sequence behavior:**
  - Initially, step 0 is active and regulation is disabled.
  - In step 0, `start` initiates regulation unless `stop` is TRUE.
  - During regulation, `settled` or `r = HIGH` terminates regulation and returns the sequence to step 0.
  - `stop` overrides all other conditions and returns the sequence to step 0.
- **A5 output behavior:**
  - During regulation, `fill_valve = TRUE` and `discharge_valve = TRUE`; `FillValve` receives the bounded PID demand scaled to 0–1000, and `DischargeValve = 400`.
  - In step 0 or whenever `stop` is TRUE, both indicators are FALSE and both analog commands are 0. Thus, “step 0 drives no output” does not mean retaining previous nonzero commands.

With linear register scaling, the target, overfill limit, and tolerance correspond respectively to **800, 900, and 20 register counts**. The model does not prescribe an additional PID-state reset policy, since the task specifies integration suspension during clamping but does not otherwise define PID initialization or reset behavior.
