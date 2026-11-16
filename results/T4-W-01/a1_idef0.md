## A0 context model

**A0 — Regulate tank level**

The function controls the Factory I/O tank level during a requested regulation cycle. It ends the cycle after sustained settling, on overfill, or on a stop command.

In IDEF0 terms:

- **Inputs** are signals or data transformed by a function.
- **Controls** are requirements, parameters, or conditions governing the transformation.
- **Outputs** are the resulting signals or data.
- **Mechanisms** are the resources performing the function.

All function names below are verb phrases; all arrow labels are noun phrases.

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Regulate tank level** | StartCommand signal (%IX100.0); StopCommand signal (%IX100.1); LevelMeter reading (%IW100) | Initial-step rule; start-event rule; stop-priority rule; regulation-completion rule; level parameters; PID gains; PID saturation and integration-suspension rules; output scaling; discharge-opening setting | FillValve command (%QW100); DischargeValve command (%QW101); fill_valve indication; discharge_valve indication | OpenPLC Runtime; PLC cyclic task; Modbus TCP connection; Factory I/O slave device and analog tank scene |

### Context controls

| Control arrow | Definition |
|---|---|
| Initial-step rule | Step 0 is the initial state; both output commands are zero. |
| Start-event rule | `start` is TRUE only in the scan detecting a press of StartCommand. A regulation cycle starts from step 0 on `start`, unless stop or overfill prevents regulation. |
| Stop-priority rule | `stop` is TRUE whenever StopCommand is TRUE. It overrides starting and regulation, returns the sequence to step 0, and makes both output commands zero. |
| Regulation-completion rule | Regulation ends on `settled` or `r = HIGH`; both valves close and the sequence returns to step 0. |
| Level parameters | \(h_{sp}=h_{target}=0.8h_{span}\); \(h_{max}=0.9h_{span}\); \(\epsilon=0.02h_{span}\); \(t_h=10\,s\); \(h_{span}=10\,V\). |
| PID gains | \(K_p,\ T_i,\ T_d\), supplied as tuning parameters. |
| PID saturation and integration-suspension rules | PID error is \(e=h_{sp}-h\). Output is clamped to 0–100%; integration is suspended while the output is clamped. |
| Output scaling | FULL_SCALE = 1000 represents 10 V; Factory I/O driver Scale = 100. |
| Discharge-opening setting | During regulation, discharge opening is 40%, corresponding to 4 V or register value 400. |

## A0 decomposition

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A1** | **Interpret commands and level measurement** | StartCommand signal; StopCommand signal; LevelMeter reading | Start-event rule; level parameters; input scaling | start; stop; measured level \(h\); level error \(e\); level region r | PLC input image; rising-edge detector; scaling and comparison operations |
| **A2** | **Supervise the regulation cycle** | start | stop; r; settled; initial-step rule; start-event rule; stop-priority rule; regulation-completion rule | Sequence state; fill_valve indication; discharge_valve indication | PLC cyclic task; sequence-state memory |
| **A3** | **Qualify sustained level settling** | Level error \(e\) | Sequence state; stop; tolerance \(\epsilon\); hold time \(t_h\) | settled | Nonretentive on-delay timer; PLC time base; absolute-value comparison |
| **A4** | **Calculate the bounded PID demand** | Level error \(e\) | fill_valve indication; stop; PID gains; PID saturation and integration-suspension rules; controller initialization policy | Bounded fill demand | PID controller; integral and derivative state memory; PLC time base |
| **A5** | **Issue the valve commands** | Bounded fill demand | fill_valve indication; discharge_valve indication; stop; output scaling; discharge-opening setting; zero-output rule | FillValve command (%QW100); DischargeValve command (%QW101) | PLC output image; Modbus TCP connection; Factory I/O driver and valve actuators |

Here, **Sequence state** is internal sequence information identifying step 0 or the regulation step. It is not an additional receptivity.

## Child-function definitions and connections

### A1 — Interpret commands and level measurement

A1 produces the required receptivity vocabulary without renaming it:

- **start**: rising-edge event from StartCommand, TRUE for one scan only.
- **stop**: current StopCommand value.
- **r**:
  - `LOW` when \(h<h_{target}\)
  - `MID` when \(h_{target}\le h<h_{max}\)
  - `HIGH` when \(h\ge h_{max}\)

Measurement conversion:

\[
h=\frac{\text{LevelMeter}}{\text{FULL\_SCALE}}h_{span},
\qquad e=h_{sp}-h
\]

Equivalent register-domain reference values are:

| Quantity | Register-domain value |
|---|---:|
| Target level | 800 |
| Overfill limit | 900 |
| Error tolerance | 20 |

Connections: **start**, **stop**, and **r** govern A2; **level error \(e\)** feeds A3 and A4. **stop** also directly governs A3–A5.

### A2 — Supervise the regulation cycle

The sequence has two steps:

| Current step | Condition, in priority order | Resulting step | Output indications after the decision |
|---|---|---|---|
| Either step | `stop` | Step 0 | `fill_valve = FALSE`; `discharge_valve = FALSE` |
| Regulation step | `r = HIGH` or `settled` | Step 0 | Both FALSE |
| Step 0 | `start` and `r ≠ HIGH`, with `stop = FALSE` | Regulation step | Both TRUE |
| Either step | No applicable transition | Current step | Both FALSE in step 0; both TRUE in regulation |

The overfill condition therefore prevents valve activation if the tank is already at or above the limit when StartCommand is pressed.

Connections: **Sequence state** controls A3; **fill_valve indication** controls A4 and A5; **discharge_valve indication** controls A5. Both indications are also abstract outputs of A0.

### A3 — Qualify sustained level settling

A3 asserts **settled** only when

\[
|e|\le\epsilon
\]

has remained continuously true for \(t_h=10\,s\) during the current regulation cycle.

The elapsed time and **settled** are reset when:

- The error leaves the tolerance band;
- The sequence is in step 0; or
- **stop** is TRUE.

Connection: **settled** feeds A2 as the normal-completion control. Time from separate visits to the tolerance band is not accumulated.

### A4 — Calculate the bounded PID demand

While **fill_valve** is TRUE and **stop** is FALSE, A4:

1. Calculates the PID demand from \(e\).
2. Clamps the demand to \(0\ldots100\%\).
3. Suspends integral accumulation while the output is clamped.

The **controller initialization policy** must be defined before coding—for example, reset controller history in step 0 and initialize derivative history at activation. The task does not specify this policy or numerical PID tuning.

Connection: **Bounded fill demand** feeds A5.

### A5 — Issue the valve commands

The **zero-output rule** makes inactive outputs zero; **stop** overrides all other controls.

| Condition | FillValve command | DischargeValve command |
|---|---:|---:|
| `stop = TRUE` | 0 | 0 |
| `fill_valve = FALSE` and `discharge_valve = FALSE` | 0 | 0 |
| Active regulation | Bounded fill demand scaled to 0–1000 | 400 |

The identifiers **fill_valve** and **discharge_valve** are Boolean functional indications, not additional mapped physical outputs:

- **fill_valve = TRUE** means the PID controls FillValve, even if its instantaneous demand is zero.
- **discharge_valve = TRUE** means DischargeValve is commanded to 40%.

The child-function connections are functional dependencies, not prescribed one-scan delays. In particular, stop, overfill, and settling completion must result in zero valve commands in the scan in which they are recognized.
