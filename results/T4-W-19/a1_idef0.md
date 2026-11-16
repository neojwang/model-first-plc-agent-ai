## A0 — Control the tank level

**Scope:** Control the Factory I/O analog Level Control scene through OpenPLC and Modbus TCP. The model covers signal interpretation, operating-step supervision, completion detection, PID calculation, and valve-output generation.

The requested **A0 context function** is decomposed into **A1–A5** below. Arrow labels are noun phrases; function names are verb phrases.

### ICOM model

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control the tank level** | StartCommand signal; StopCommand signal; LevelMeter register value | I/O mapping specification; FULL_SCALE; measuring span h_span; level target h_sp = h_target; overfill limit h_max; tolerance eps; hold time t_h; PID gains Kp, Ti, Td; operating-step rules; output-clamping rule; integration-suspension rule; stop-priority rule | FillValve register command; DischargeValve register command | OpenPLC Runtime; cyclic PLC task and clock; Modbus TCP connection; Factory I/O slave device; tank, level meter, and valves |
| **A1** | **Interpret the command and measurement signals** | StartCommand signal; StopCommand signal; LevelMeter register value | Input address mapping; FULL_SCALE; measuring span h_span; rising-edge detection rule | **start**; **stop**; measured level h | OpenPLC input image; Modbus TCP interface; previous-button-state memory |
| **A2** | **Evaluate the level conditions** | Measured level h | Level target h_sp = h_target; overfill limit h_max; tolerance eps; hold time t_h; operating step; timer-reset rule | Level error e; **r**; **settled** | PLC arithmetic facilities; continuous-dwell timer; cyclic PLC clock |
| **A3** | **Supervise the operating step** | **start**; **stop**; **r**; **settled** | Initial-step rule; start-transition rule; completion-transition rule; stop-priority rule | Operating step; **fill_valve**; **discharge_valve** | PLC step-state memory; cyclic PLC execution |
| **A4** | **Calculate the bounded PID demand** | Level error e | **fill_valve**; **stop**; PID gains Kp, Ti, Td; PID execution interval; 0–100% output limits; integration-suspension rule | Bounded fill demand | PID arithmetic facilities; integral-state memory; derivative-history memory; cyclic PLC clock |
| **A5** | **Generate the valve register commands** | Bounded fill demand | **fill_valve**; **discharge_valve**; **stop**; FULL_SCALE; 40% discharge-opening specification; output address mapping; zero-output rule | FillValve register command; DischargeValve register command | OpenPLC output image; integer-conversion facilities; Modbus TCP interface; Factory I/O valve actuators |

## Arrow definitions

### External arrows

| Arrow | Definition |
|---|---|
| StartCommand signal | BOOL input at **%IX100.0**. |
| StopCommand signal | BOOL input at **%IX100.1**. |
| LevelMeter register value | INT input at **%IW100**, proportional to the level-meter voltage. |
| FULL_SCALE | Register value **1000**, corresponding to **10 V**, with Factory I/O driver **Scale = 100**. |
| FillValve register command | INT output at **%QW100**, in the range **0–1000**. |
| DischargeValve register command | INT output at **%QW101**, either **0** or **400** under this task. |

### Internal arrows and connections

| Arrow | Source → Destination | Meaning |
|---|---|---|
| **start** | A1 → A3 | StartCommand rising-edge event; TRUE only for the scan in which the button is pressed. |
| **stop** | A1 → A3, A4, A5 | StopCommand level; TRUE throughout a stop request. |
| Measured level h | A1 → A2 | Scaled level: h = LevelMeter / FULL_SCALE × h_span. |
| Level error e | A2 → A4 | Difference h_sp − h. |
| **r** | A2 → A3 | Level region: LOW, MID, or HIGH, as defined below. |
| **settled** | A2 → A3 | Continuous in-band dwell completion during regulation. |
| Operating step | A3 → A2 | Current step: step 0 or regulation step; governs dwell-timer eligibility and reset. |
| **fill_valve** | A3 → A4, A5 | BOOL permission: TRUE while the PID drives the fill valve. |
| **discharge_valve** | A3 → A5 | BOOL permission: TRUE while the discharge valve is held at 40%. |
| Bounded fill demand | A4 → A5 | PID fill-opening demand limited to 0–100%. |

**fill_valve** and **discharge_valve** are logical output permissions, not the analog register values. A5 converts these permissions and the PID demand into the physical output commands.

## Functional controls and operating rules

### A1 — Signal interpretation

Use a common level basis throughout the model:

- h_sp = h_target = **0.8 h_span**
- h_max = **0.9 h_span**
- eps = **0.02 h_span**

On the register-equivalent basis, these correspond to a target of **800**, an overfill limit of **900**, and a tolerance of **20** counts.

### A2 — Level-condition evaluation

The region arrow **r** has exactly these values:

| Value | Condition |
|---|---|
| **LOW** | h < h_target |
| **MID** | h_target ≤ h < h_max |
| **HIGH** | h ≥ h_max |

The dwell timer runs only while regulation is active and |e| ≤ eps. It resets when regulation is inactive or |e| > eps. **settled** becomes TRUE after **10 s of uninterrupted in-band operation**; elapsed time is not accumulated across separate in-band intervals.

### A3 — Step supervision

| Priority | Condition | Result |
|---|---|---|
| Highest | **stop** = TRUE, from any step | Step 0; **fill_valve** = FALSE; **discharge_valve** = FALSE. |
| Next | Regulation active and either **settled** = TRUE or **r** = HIGH | Step 0; both permissions FALSE. |
| Next | Step 0 and **start** = TRUE, with **stop** = FALSE and **r** ≠ HIGH | Regulation step; both permissions TRUE. |
| Otherwise | No applicable transition | Existing step retained. |

Step 0 is the initial step and commands no valve opening. A start event at **r = HIGH** does not produce a one-scan valve-opening pulse. A held StartCommand does not restart regulation after completion; another rising edge is required.

### A4 — PID calculation

During regulation:

- Calculate the PID demand using **e = h_sp − h**.
- Clamp the demand to **0–100%**.
- Suspend integration whenever the output is clamped.
- Produce no active fill demand when **fill_valve** is FALSE or **stop** is TRUE.

PID initialization and inactive-state handling must be defined during detailed design; no particular reset or retained-integral policy is specified by the task.

### A5 — Output generation

- With **fill_valve** TRUE and **stop** FALSE: scale the bounded PID demand to **0–1000** for FillValve.
- With **discharge_valve** TRUE and **stop** FALSE: command **400** for DischargeValve.
- In step 0, or whenever **stop** is TRUE: command **0 to both registers**.

Stop and completion decisions must govern the output commands in the same PLC scan, rather than allowing stale PID or discharge commands to reach the output image.
