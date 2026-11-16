The model below separates signal interpretation, sequence supervision, settling detection, PID calculation, and output generation. **A0** is the context function; **A1–A5** are its child functions. In strict IDEF0 diagram notation, the context diagram is **A-0**, containing function box **A0**.

The identifiers **start**, **stop**, **settled**, **r**, **fill_valve**, and **discharge_valve** retain their specified meanings. In particular, **fill_valve** and **discharge_valve** are Boolean activity indicators, not the analog valve commands.

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control tank level** | StartCommand samples; StopCommand samples; LevelMeter samples | Set point \(h_{sp}=h_{target}=0.8h_{span}\); overfill limit \(h_{max}=0.9h_{span}\); tolerance \(\varepsilon=0.02h_{span}\); hold time \(t_h=10\,s\); PID gains \(K_p,T_i,T_d\); measuring span \(h_{span}\); FULL_SCALE = 1000; discharge opening of 40%; initial-step, start-event, stop-priority, termination, saturation, and integration-suspension rules; I/O address mapping | Fill-valve analog command; discharge-valve analog command | OpenPLC Runtime; PLC program and cyclic execution; Factory I/O Modbus TCP interface |
| **A1** | **Interpret command and level samples** | StartCommand samples; StopCommand samples; LevelMeter samples; previous StartCommand sample | Rising-edge definition of **start**; level-scaling relationship; FULL_SCALE; \(h_{span}\); \(h_{sp}\); \(h_{target}\); \(h_{max}\); input address mapping | **start**; **stop**; measured level \(h\); level error \(e\); level region **r**; updated StartCommand history | OpenPLC input acquisition; edge-detection logic; scaling and comparison logic |
| **A2** | **Supervise regulation sequence** | Previous sequence state | **start**; **stop**; **settled**; **r**; initial state of step 0; stop-priority rule; regulation-entry and termination rules | Updated sequence state; **fill_valve**; **discharge_valve** | OpenPLC sequence logic; retained scan-to-scan state storage |
| **A3** | **Evaluate settling condition** | Level error \(e\); previous settling-timer state | **fill_valve**; tolerance \(\varepsilon\); hold time \(t_h\); uninterrupted-band timing rule; timer-reset rule | **settled**; updated settling-timer state | OpenPLC timer; cyclic time base; tolerance-comparison logic |
| **A4** | **Calculate bounded PID demand** | Level error \(e\); previous PID state | **fill_valve**; PID gains \(K_p,T_i,T_d\); execution interval; output limits of 0–100%; integration-suspension rule during clamping | Bounded fill-opening demand; updated PID state | OpenPLC PID calculation; saturation logic; integral-state gating; PID state storage |
| **A5** | **Generate valve commands** | Bounded fill-opening demand | **fill_valve**; **discharge_valve**; **stop**; FULL_SCALE; discharge opening of 40%; inactive-output zeroing rule; integer-conversion rule; output address mapping | Fill-valve analog command at %QW100; discharge-valve analog command at %QW101 | OpenPLC output assignment; Modbus TCP output interface |

### Arrow definitions and governing rules

- **Signal interpretation**
  - **start** is TRUE only on the rising edge of StartCommand.
  - **stop** follows StopCommand.
  - \(h=(\text{LevelMeter}/1000)\,h_{span}\), and \(e=h_{sp}-h\).
  - **r** = LOW when \(h<h_{target}\), MID when \(h_{target}\le h<h_{max}\), and HIGH when \(h\ge h_{max}\).

- **Sequence supervision**
  - Step 0 is the initial, inactive state: **fill_valve** = FALSE and **discharge_valve** = FALSE.
  - **start** initiates regulation, provided **stop** is FALSE and **r** is not HIGH.
  - During regulation, both activity indicators are TRUE.
  - **settled**, **r** = HIGH, or **stop** returns the sequence to step 0. **stop** has priority over all other conditions.
  - A held StartCommand does not restart regulation; a new **start** event is required.

- **Settling detection**
  - **settled** becomes TRUE only after \(|e|\le\varepsilon\) has remained continuously true for \(10\,s\) during regulation.
  - The settling timer resets when the level leaves the tolerance band or regulation becomes inactive.

- **PID and command generation**
  - A4 clamps the PID demand to 0–100% and suspends integration while the output is clamped.
  - When **fill_valve** is TRUE, A5 converts that demand to an integer command in 0–1000.
  - When **discharge_valve** is TRUE, the discharge command is \(0.4\times1000=400\).
  - Inactive activity indicators produce zero commands; **stop** forces both commands to zero.

The sequence-state, command-history, timer-state, and PID-state arrows are internal feedback arrows, not additional external plant I/O.
