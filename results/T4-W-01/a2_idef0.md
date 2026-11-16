### IDEF0 functional model

**A0** is the context function; **A1–A6** are its child functions. Inputs are transformed data, controls govern function execution, outputs are produced results, and mechanisms are the resources performing the functions.

The required identifiers **start, stop, settled, r, fill_valve, discharge_valve** are retained exactly. In particular, **fill_valve** and **discharge_valve** are Boolean activity indications, not the analog output-register values.

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control tank level** | StartCommand samples; StopCommand samples; LevelMeter samples | Initial-step rule; start-event rule; stop-priority rule; level set point and limits; tolerance and hold-time criteria; PID gains; output-clamping and integration-suspension rules; discharge-opening requirement; I/O mapping and scaling | FillValve command; DischargeValve command; **fill_valve**; **discharge_valve** | OpenPLC Runtime and PLC program; Modbus TCP connection; Factory I/O analog level-control plant, including level meter and valves |
| **A1** | **Acquire and interpret plant signals** | StartCommand samples; StopCommand samples; LevelMeter samples | I/O address mapping; FULL_SCALE and level scaling; rising-edge detection rule | **start**; **stop**; measured level *h* | PLC input acquisition; rising-edge detector with previous-sample memory; scaling logic; Modbus TCP interface |
| **A2** | **Evaluate level conditions** | Measured level *h* | Set point *h_sp = h_target*; overfill limit *h_max*; tolerance *eps*; hold time *t_h*; regulation state; hold-timer reset rule | Level error *e*; **r**; **settled** | PLC arithmetic and comparison logic; continuous-condition hold timer |
| **A3** | **Supervise regulation sequence** | **start**; **stop**; **r**; **settled** | Initial state: step 0; **stop** priority; start acceptance in step 0; regulation termination on **settled** or **r = HIGH** | Regulation state; **fill_valve**; **discharge_valve**; controller reset request | PLC sequence/state logic; state memory |
| **A4** | **Calculate bounded PID demand** | Level error *e* | PID gains *Kp, Ti, Td*; control-cycle interval; regulation state; controller reset request; output limits of 0–100%; integration suspension while output is clamped | Bounded fill-opening demand | PLC PID algorithm; integral and derivative state memory |
| **A5** | **Form valve commands** | Bounded fill-opening demand | **fill_valve**; **discharge_valve**; FULL_SCALE; fixed discharge opening of 40%; zero-output requirement outside regulation | FillValve command; DischargeValve command | PLC output-selection and numeric-conversion logic |
| **A6** | **Apply valve commands** | FillValve command; DischargeValve command | Output address mapping; analog-output scaling | FillValve register value at %QW100; DischargeValve register value at %QW101 | PLC output image; Modbus TCP interface; Factory I/O driver and valve actuators |

### Arrow and control definitions

- **Signal interpretation**
  - **start** is TRUE only for the scan detecting a rising edge of StartCommand.
  - **stop** follows StopCommand.
  - With level expressed as a fraction of span, \(h=\text{LevelMeter}/1000\). Thus the set point, overfill limit, and tolerance correspond to **800**, **900**, and **20** register counts.

- **Level evaluation**
  - \(e=h_{sp}-h\).
  - **r = LOW** for \(h<h_{target}\).
  - **r = MID** for \(h_{target}\le h<h_{max}\).
  - **r = HIGH** for \(h\ge h_{max}\).
  - **settled** becomes TRUE after \(|e|\le eps\) has remained continuously true for **10 s during regulation**. The hold timer resets outside regulation or whenever the tolerance condition becomes false.

- **Sequence supervision**
  - Step 0 is the initial state: **fill_valve = FALSE**, **discharge_valve = FALSE**, and both analog commands are zero.
  - **start** in step 0 initiates regulation, provided **stop** is FALSE.
  - During regulation, both Boolean activity indications are TRUE.
  - **settled**, **r = HIGH**, or **stop** ends regulation and closes both valves. **stop** overrides starting or continued regulation.

- **Command formation**
  - While **fill_valve** is TRUE, FillValve receives the PID demand clamped to **0–1000** counts; otherwise it receives **0**.
  - While **discharge_valve** is TRUE, DischargeValve receives **400** counts; otherwise it receives **0**.
  - The PID integral is suspended whenever its output is clamped. The controller reset request prepares controller state for the next regulation episode; the task does not prescribe a particular PID-state initialization algorithm.

The regulation state and controller reset request are internal feedback arrows from A3 to the evaluation and PID functions; they are not additional external plant I/O.
