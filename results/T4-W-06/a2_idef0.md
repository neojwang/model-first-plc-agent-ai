The model below treats the function as **PLC-based tank-level control**, rather than the physical filling and draining of the tank. Thus, measured signals are inputs, valve commands are outputs, operating requirements are controls, and the PLC and communication facilities are mechanisms.

**A0 is the context function; A1–A5 are its child functions.** Names such as `start`, `settled`, and `fill_valve` retain the required vocabulary.

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control tank level** | StartCommand signal (%IX100.0); StopCommand signal (%IX100.1); LevelMeter value (%IW100) | I/O mapping and scaling specification; FULL_SCALE = 1000; h_span; h_sp = h_target = 0.8 h_span; h_max = 0.9 h_span; eps = 0.02 h_span; t_h = 10 s; PID gains Kp, Ti, Td; initial-step rule; start-event rule; stop-priority rule; completion rules; PID saturation and integration-suspension rules; 40% discharge-opening requirement | FillValve command (%QW100); DischargeValve command (%QW101); logical output indications `fill_valve` and `discharge_valve` | OpenPLC Runtime; PLC scan and clock; controller memory; Modbus TCP connection; Factory I/O driver and analog Level Control scene |
| **A1** | **Interpret command and level signals** | StartCommand signal; StopCommand signal; LevelMeter value | I/O mapping; FULL_SCALE and h_span scaling; rising-edge definition of `start`; h_sp and h_target values; h_max threshold; error definition e = h_sp − h; level-region definitions | `start` event; `stop` condition; measured level h; level error e; level region `r` | PLC input image; edge-detection logic and previous-sample memory; arithmetic and comparison logic |
| **A2** | **Determine sustained settling** | Level error e | Regulation-active status; tolerance eps; hold time t_h; continuous-in-band timing rule; timer-reset rule on loss of the in-band condition or termination of regulation | `settled` condition | PLC timer; scan clock; timer state memory |
| **A3** | **Manage regulation sequence** | `start` event; `stop` condition; `settled` condition; level region `r` | Initial step 0; transition from step 0 on `start`; termination on `settled` or `r = HIGH`; overriding stop priority; inactive-output requirement | Sequence step; regulation-active status; logical output indications `fill_valve` and `discharge_valve` | PLC sequence logic; step-state memory |
| **A4** | **Compute bounded PID demand** | Level error e | Regulation-active status; PID gains Kp, Ti, Td; output limits of 0–100%; integration suspension while the output is clamped | Bounded fill-opening demand | PLC PID algorithm; integral and derivative state memory; scan-time measurement |
| **A5** | **Generate valve commands** | Bounded fill-opening demand | Logical output indications `fill_valve` and `discharge_valve`; FULL_SCALE = 1000; 40% discharge-opening requirement; zero-output requirement in step 0 and on stop | FillValve command (%QW100); DischargeValve command (%QW101) | PLC output-scaling and gating logic; output image; Modbus TCP connection; Factory I/O driver |

### Arrow definitions and operating interpretation

- **`start`**: TRUE only in the scan detecting a press of StartCommand; a continuously held button does not generate repeated start events.
- **`stop`**: the current StopCommand condition. It overrides starting or continued regulation.
- **`r`**:
  - `LOW`: h < h_target
  - `MID`: h_target ≤ h < h_max
  - `HIGH`: h ≥ h_max
- **`settled`**: TRUE when |e| ≤ eps has remained continuously true for 10 seconds during regulation.
- **`fill_valve`**: TRUE while regulation enables PID control of the fill valve.
- **`discharge_valve`**: TRUE while regulation enables the fixed 40% discharge opening.

The logical indications `fill_valve` and `discharge_valve` are **enable conditions, not additional physical I/O addresses**. In particular, `fill_valve` can be TRUE while the PID demand—and therefore the physical fill-valve command—is zero.

With the specified scaling, h_sp corresponds to **800**, h_max to **900**, and eps to **20 register counts**. A5 produces a fill command in **0–1000** and a discharge command of **400** during regulation. In step 0, including after completion or stop, both physical commands are **0**.
