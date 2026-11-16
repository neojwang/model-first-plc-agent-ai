## A0 context model — Regulate tank level

The model below uses **A0** for the requested context function and **A1–A6** for its decomposition. Function names are verb phrases; arrow names are noun phrases. In strict FIPS 183 diagram numbering, the context diagram containing the A0 box is normally designated **A-0**.

**System boundary:** PLC control logic. The Factory I/O tank and operator supply inputs; the PLC produces the two analog valve commands.

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Regulate tank level** | StartCommand signal; StopCommand signal; LevelMeter register value | I/O mapping and scaling specification; level set point; overfill limit; tolerance band; hold-time requirement; PID gains; PID saturation and integration-suspension rule; discharge-opening requirement; initial-step rule; stop-priority rule | FillValve register command; DischargeValve register command | OpenPLC Runtime; PLC scan clock; Modbus TCP connection; Factory I/O analog I/O interface |

### Boundary-arrow definitions

| Arrow | Definition |
|---|---|
| StartCommand signal | `StartCommand AT %IX100.0 : BOOL` |
| StopCommand signal | `StopCommand AT %IX100.1 : BOOL` |
| LevelMeter register value | `LevelMeter AT %IW100 : INT` |
| FillValve register command | `FillValve AT %QW100 : INT` |
| DischargeValve register command | `DischargeValve AT %QW101 : INT` |
| I/O mapping and scaling specification | Listed addresses; Factory I/O driver `Scale = 100`; `FULL_SCALE = 1000`, corresponding to 10 V |
| Level set point | \(h_{sp}=h_{target}=0.8h_{span}\) |
| Overfill limit | \(h_{max}=0.9h_{span}\) |
| Tolerance band | \(\varepsilon=0.02h_{span}\) |
| Hold-time requirement | \(t_h=10\,s\), continuously within the tolerance band |
| PID gains | \(K_p,\ T_i,\ T_d\) |
| Discharge-opening requirement | 40% opening during regulation |

## A0 decomposition

The required identifiers **start**, **stop**, **settled**, **r**, **fill_valve**, and **discharge_valve** are retained exactly. The last two are internal Boolean output authorizations, not analog register values.

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A1** | **Interpret commands and level** | StartCommand signal; StopCommand signal; LevelMeter register value | I/O mapping and scaling specification; level set point; overfill limit | **start**; **stop**; measured level \(h\); level error \(e\); **r** | Input image; rising-edge detector; arithmetic and comparison facilities |
| **A2** | **Evaluate continuous settling** | Level error \(e\) | Tolerance band; hold-time requirement; **fill_valve** | **settled** | Resettable on-delay timer; PLC scan clock |
| **A3** | **Manage regulation steps** | — | **start**; **stop**; **settled**; **r**; initial-step rule; stop-priority rule | Step state; **fill_valve**; **discharge_valve** | Two-step state sequencer; state memory |
| **A4** | **Calculate PID demand** | Level error \(e\) | **fill_valve**; PID gains; PID saturation and integration-suspension rule | Limited fill-opening demand | PID calculation facility; PID state memory; PLC scan clock |
| **A5** | **Form valve register commands** | Limited fill-opening demand | **fill_valve**; **discharge_valve**; discharge-opening requirement; I/O mapping and scaling specification | FillValve register command; DischargeValve register command | Scaling and integer-conversion facilities; output image |
| **A6** | **Transfer valve commands** | FillValve register command; DischargeValve register command | I/O mapping and scaling specification | Transmitted FillValve register command; transmitted DischargeValve register command | OpenPLC Runtime; Modbus TCP connection; Factory I/O analog I/O interface |

**Boundary balancing:** A6’s transmitted commands are the physical-interface realization of A0’s FillValve and DischargeValve register-command outputs; they are not additional independent commands.

## Internal-arrow definitions and routing

| Arrow | Definition | Source → destination |
|---|---|---|
| **start** | One-scan event on the rising edge of StartCommand | A1 → A3 |
| **stop** | Current Boolean value of StopCommand | A1 → A3 |
| Measured level \(h\) | \(h=(\text{LevelMeter}/\text{FULL_SCALE})h_{span}\) | A1 → internal observation |
| Level error \(e\) | \(h_{sp}-h\) | A1 → A2, A4 |
| **r** | `LOW` for \(h<h_{target}\); `MID` for \(h_{target}\le h<h_{max}\); `HIGH` for \(h\ge h_{max}\) | A1 → A3 |
| **settled** | Continuous in-band duration of at least \(t_h\) during regulation | A2 → A3 |
| Step state | Step 0: idle; step 1: regulation | A3 → internal observation |
| **fill_valve** | Boolean authorization for PID-driven filling | A3 → A2, A4, A5 |
| **discharge_valve** | Boolean authorization for fixed 40% discharge | A3 → A5 |
| Limited fill-opening demand | PID demand limited to 0–100% | A4 → A5 |
| FillValve register command | Integer command in the range 0–1000 | A5 → A6 → A0 boundary |
| DischargeValve register command | Integer command of 0 or 400 | A5 → A6 → A0 boundary |

## Functional constraints

### Step management — A3

| Current condition | Result |
|---|---|
| Initialization | Step 0; **fill_valve** = FALSE; **discharge_valve** = FALSE |
| **stop** = TRUE, in any step | Step 0; both authorizations FALSE |
| Step 0, **start** = TRUE, no overriding stop or overfill condition | Step 1 |
| Step 1, **settled** = TRUE or **r** = `HIGH` | Step 0; both authorizations FALSE |
| Step 1, no termination condition | Remain in step 1; both authorizations TRUE |
| Step 0, no accepted **start** event | Remain in step 0 |

Stop has highest priority. An overfill condition must not produce a valve-opening pulse on entry to regulation. A completed cycle does not restart from a continuously held StartCommand; another **start** event is required.

### Settling evaluation — A2

- Timing is enabled only while **fill_valve** is TRUE.
- The timer accumulates only while \(|e|\le\varepsilon\).
- Leaving the tolerance band or leaving regulation resets the timer and **settled**.
- The 10 seconds are therefore **continuous**, not cumulative.

### PID calculation — A4

- The PID acts on \(e=h_{sp}-h\).
- Its fill-opening demand is limited to 0–100%.
- Integration is suspended whenever the unconstrained demand would lie outside those limits.
- PID execution is disabled outside regulation. PID initialization and restart treatment must be specified before implementation; the task does not prescribe an integrator preload or derivative-initialization method.

### Output formation — A5

\[
\text{FillValve}=
\begin{cases}
\operatorname{INT}\!\left(\text{FULL\_SCALE}\,\dfrac{u_{\text{limited}}}{100}\right),
& \textbf{fill\_valve}=\text{TRUE}\\
0,& \text{otherwise}
\end{cases}
\]

\[
\text{DischargeValve}=
\begin{cases}
0.4\,\text{FULL\_SCALE}=400,
& \textbf{discharge\_valve}=\text{TRUE}\\
0,& \text{otherwise}
\end{cases}
\]

Thus, step 0 explicitly commands **both outputs to zero**, rather than merely ceasing to update them.
