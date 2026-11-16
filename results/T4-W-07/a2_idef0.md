**Model boundary:** the PLC-based level-control system, including acquisition and scaling of scene signals, sequencing, PID computation, timing, and output generation. The tank is the controlled plant; its measured level is feedback to the system.

In the table, **inputs** are information transformed by a function, **controls** govern its execution, **outputs** are its results, and **mechanisms** are the resources that perform it. A0 is the context function; A1–A5 are its child functions.

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control tank level** | StartCommand signal; StopCommand signal; LevelMeter reading | Initial-step rule; start-event rule; stop-priority rule; level set point \(h_{sp}=h_{target}=0.8h_{span}\); overfill limit \(h_{max}=0.9h_{span}\); tolerance \(\varepsilon=0.02h_{span}\); hold time \(t_h=10\,s\); PID gains \(K_p,T_i,T_d\); PID output limits of 0–100%; integration-suspension rule during clamping; discharge opening of 40%; FULL_SCALE = 1000; I/O mapping and scaling specification | **fill_valve**; **discharge_valve**; FillValve register command; DischargeValve register command | OpenPLC Runtime; PLC control program; Factory I/O Modbus TCP interface; PLC scan clock |
| **A1** | **Acquire and interpret process signals** | StartCommand signal at `%IX100.0`; StopCommand signal at `%IX100.1`; LevelMeter reading at `%IW100` | Rising-edge detection rule for **start**; FULL_SCALE = 1000; measuring span \(h_{span}\); set point \(h_{target}\); overfill limit \(h_{max}\); level-scaling and region-classification rules | **start**; **stop**; measured level \(h\); level error \(e=h_{sp}-h\); **r** | PLC input image; Modbus TCP interface; edge-detection logic; scaling and comparison logic |
| **A2** | **Determine sustained level settling** | Level error \(e\) | Regulation state; tolerance \(\varepsilon\); hold time \(t_h\); continuous-in-band timing rule; timer-reset rule outside the band or outside regulation | **settled** | PLC timer; PLC scan clock; tolerance-comparison logic |
| **A3** | **Manage regulation steps** | **start** | **stop**; **settled**; **r**; initial step 0; stop-priority rule; start-transition rule; regulation-completion rule | Regulation state; **fill_valve**; **discharge_valve** | PLC sequence logic; step-state memory |
| **A4** | **Calculate bounded PID demand** | Level error \(e\) | Regulation state; **fill_valve**; PID gains \(K_p,T_i,T_d\); scan interval; output limits of 0–100%; integration-suspension rule while the PID output is clamped | Bounded fill-opening demand | PLC PID algorithm; integral and derivative state memory; PLC scan clock |
| **A5** | **Generate valve register commands** | Bounded fill-opening demand | **fill_valve**; **discharge_valve**; **stop**; FULL_SCALE = 1000; discharge-opening setting of 40%; inactive-step and stop zero-output rules; output-address mapping | FillValve register command at `%QW100`; DischargeValve register command at `%QW101` | PLC output logic; PLC output image; Modbus TCP interface |

### Arrow meanings and governing behavior

- **start** is a one-scan event produced on a rising edge of StartCommand—not a continuously asserted start request.
- **stop** is the current Boolean value of StopCommand.
- **r** is the level-region classification:
  - `LOW`: \(h<h_{target}\)
  - `MID`: \(h_{target}\le h<h_{max}\)
  - `HIGH`: \(h\ge h_{max}\)
- **settled** becomes TRUE only after \(|e|\le\varepsilon\) has remained continuously true for \(10\,s\) during regulation. Leaving the band or ending regulation resets that timing.
- **A3 sequencing:**
  - Initially, step 0 is active and both **fill_valve** and **discharge_valve** are FALSE.
  - In step 0, **start** enters regulation only when **stop** is FALSE.
  - During regulation, both flags are TRUE.
  - **settled** or `r = HIGH` ends regulation and returns to step 0.
  - **stop** overrides all other conditions and returns to step 0.
- **A5 output conversion:**
  - When **fill_valve** is TRUE, `%QW100` receives the bounded PID opening scaled to \(0\ldots1000\); otherwise it receives 0.
  - When **discharge_valve** is TRUE, `%QW101` receives 400; otherwise it receives 0.
  - Whenever **stop** is TRUE, both register commands are 0.

The names **fill_valve** and **discharge_valve** denote the required Boolean activity indicators; they are distinct from the numerical analog register commands.
