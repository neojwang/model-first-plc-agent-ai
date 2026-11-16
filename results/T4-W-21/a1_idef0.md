## A0 context: Control tank level

The model covers the PLC control function, from acquisition of the mapped Factory I/O signals to generation of the two analog valve commands. The tank is the external process being controlled.

All function names below are **verb phrases**. Arrow labels are **noun phrases**, including the required identifiers `start`, `stop`, `settled`, `r`, `fill_valve`, and `discharge_valve`.

### Modeling conventions

Use normalized level quantities:

\[
h=\frac{\text{LevelMeter}}{\text{FULL\_SCALE}},\qquad
h_{\text{target}}=h_{sp}=0.8,\qquad
h_{\max}=0.9,\qquad
\varepsilon=0.02
\]

Thus, the measuring span is represented as 1.0. The equivalent nominal register values are 800 for the target, 900 for the overfill limit, and 20 for the tolerance.

- `start`: rising-edge event from `StartCommand`, TRUE for one scan only.
- `stop`: current Boolean value of `StopCommand`.
- `settled`: indication that \(|e|\leq\varepsilon\) has remained continuously TRUE for 10 s **during regulation**.
- `r`: level region, with values `LOW`, `MID`, and `HIGH`.
- `fill_valve`: Boolean permission indicating that the PID drives the fill valve.
- `discharge_valve`: Boolean permission indicating that the discharge valve is held at 40%.

The last two identifiers are logical output permissions, **not** the analog register values.

## ICOM model

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control tank level** | StartCommand signal (`%IX100.0`); StopCommand signal (`%IX100.1`); LevelMeter value (`%IW100`) | I/O mapping specification; FULL_SCALE value (1000); level set point (0.8 span); overfill limit (0.9 span); tolerance band (0.02 span); hold-time setting (10 s); PID gains (`Kp`, `Ti`, `Td`); output limits (0–100%); integration-suspension rule; discharge-opening setting (40%); initialization rule; stop-priority rule; sequence-transition rules | FillValve command (`%QW100`); DischargeValve command (`%QW101`) | OpenPLC controller and runtime; scan clock; Modbus TCP connection; Factory I/O driver with Scale = 100 |
| **A1** | **Acquire and normalize process signals** | StartCommand signal; StopCommand signal; LevelMeter value | I/O mapping specification; FULL_SCALE value; rising-edge detection rule | `start`; `stop`; normalized level | OpenPLC input image; edge-detection memory; scaling arithmetic |
| **A2** | **Evaluate regulation conditions** | Normalized level | Level set point; overfill limit; tolerance band; hold-time setting; regulation status; scan timing | Level error; `r`; `settled` | OpenPLC arithmetic and comparison functions; non-retentive on-delay timer |
| **A3** | **Manage regulation sequence** | — | `start`; `stop`; `settled`; `r`; initialization rule; stop-priority rule; sequence-transition rules | Regulation status; `fill_valve`; `discharge_valve` | OpenPLC sequence logic; step-state memory |
| **A4** | **Calculate bounded PID demand** | Level error | `fill_valve`; PID gains; scan timing; output limits; integration-suspension rule | Bounded fill demand | OpenPLC PID calculation; PID state memory; saturation logic |
| **A5** | **Generate analog valve commands** | Bounded fill demand | `fill_valve`; `discharge_valve`; `stop`; FULL_SCALE value; discharge-opening setting; I/O mapping specification; zero-output rule | FillValve command; DischargeValve command | OpenPLC output image; numeric conversion and limiting functions; Modbus TCP connection; Factory I/O driver |

Here, **regulation status** is the state indication used to enable and reset qualification timing. It is not an additional external receptivity.

## Child-function connections

These connections define the internal arrows of the A0 decomposition.

| Arrow | Source | Destination | Role at destination |
|---|---|---|---|
| `start` | A1 | A3 | Control |
| `stop` | A1 | A3, A5 | Control |
| Normalized level | A1 | A2 | Input |
| Level error | A2 | A4 | Input |
| `r` | A2 | A3 | Control |
| `settled` | A2 | A3 | Control |
| Regulation status | A3 | A2 | Control |
| `fill_valve` | A3 | A4, A5 | Control |
| `discharge_valve` | A3 | A5 | Control |
| Bounded fill demand | A4 | A5 | Input |

The external inputs, controls, outputs, and mechanisms of the child functions are branches of the corresponding A0 boundary arrows. No additional external signal is introduced.

## Functional rules attached to the model

### A1 — Acquire and normalize process signals

- Detect the rising edge of `StartCommand` to produce `start`.
- Pass the current `StopCommand` value as `stop`.
- Scale `LevelMeter` using `FULL_SCALE = 1000`.

A continuously held Start button does not generate repeated `start` events.

### A2 — Evaluate regulation conditions

Calculate:

\[
e=h_{sp}-h
\]

Classify the level:

\[
r=
\begin{cases}
\text{LOW}, & h<h_{\text{target}}\\
\text{MID}, & h_{\text{target}}\le h<h_{\max}\\
\text{HIGH}, & h\ge h_{\max}
\end{cases}
\]

Qualify `settled` using continuous residence within the tolerance band:

- Enable timing only during regulation.
- Reset timing whenever regulation is inactive or \(|e|>\varepsilon\).
- Assert `settled` when the enabled interval reaches 10 s.

### A3 — Manage regulation sequence

IDEF0 describes functional relationships rather than execution order. The following state rules specify the sequencing controlled by A3:

| Current step | Condition, in priority order | Resulting step | Output permissions |
|---|---|---|---|
| Any step | `stop` | Step 0 | `fill_valve = FALSE`; `discharge_valve = FALSE` |
| Step 0 | `start` AND NOT `stop` | Regulation step | Both permissions TRUE, unless an immediate termination condition applies |
| Step 0 | No accepted `start` | Step 0 | Both permissions FALSE |
| Regulation step | `settled` OR `r = HIGH` | Step 0 | Both permissions FALSE |
| Regulation step | No termination condition | Regulation step | Both permissions TRUE |

Additional sequence constraints:

- Initialization selects **Step 0**.
- Step 0 has no active output action; both analog commands are zero.
- `stop` overrides every other condition.
- Entry into regulation must not produce an output pulse when `r = HIGH`.
- Completion returns to Step 0 without accepting another start transition in the same scan.

### A4 — Calculate bounded PID demand

While `fill_valve` is TRUE:

- Calculate the PID demand from \(e\), using `Kp`, `Ti`, and `Td`.
- Limit the applied demand to \(0\ldots100\%\).
- Suspend integration whenever saturation clamps the demand.
- Apply integration-suspension handling to the current scan’s integral update so that clamping does not accumulate integral windup.

While `fill_valve` is FALSE, the PID cannot drive the physical output. PID state initialization or retention on a subsequent start is a design detail to specify before implementation; the task does not prescribe it.

### A5 — Generate analog valve commands

Let the bounded fill demand \(u\) be expressed as a fraction from 0 to 1:

\[
\text{FillValve}=
\begin{cases}
\operatorname{INT}(u\cdot1000), & \text{fill\_valve AND NOT stop}\\
0, & \text{otherwise}
\end{cases}
\]

\[
\text{DischargeValve}=
\begin{cases}
400, & \text{discharge\_valve AND NOT stop}\\
0, & \text{otherwise}
\end{cases}
\]

The fill command is constrained to the integer range 0–1000. When Step 0 is selected, regulation ends, or `stop` is TRUE, both commands are zero.
