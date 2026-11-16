## Model scope and conventions

**A0 — Control tank level** models the PLC controller, not the tank dynamics. Its boundary inputs are the mapped plant signals; its boundary outputs are the two analog valve commands.

In FIPS 183 terminology, the context diagram is **A-0**, containing function **A0**. The decomposition of A0 contains **A1–A5** below.

- **Inputs** are signals or data transformed by a function.
- **Controls** are rules, parameters, and constraints governing that transformation.
- **Outputs** are resulting signals or data.
- **Mechanisms** are the resources executing the function.
- All arrow labels below are noun phrases or signal identifiers. The required receptivity and logical-output identifiers are used exactly: `start`, `stop`, `settled`, `r`, `fill_valve`, and `discharge_valve`.

## IDEF0 ICOM model

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control tank level** | Start-command signal `StartCommand` at `%IX100.0`;<br>Stop-command signal `StopCommand` at `%IX100.1`;<br>Level-meter register value `LevelMeter` at `%IW100` | I/O mapping and analog scaling specification;<br>`FULL_SCALE = 1000`;<br>Level span `h_span`;<br>Target level `h_sp = h_target = 0.8 h_span`;<br>Overfill limit `h_max = 0.9 h_span`;<br>Tolerance `eps = 0.02 h_span`;<br>Hold time `t_h = 10 s`;<br>PID parameters `Kp`, `Ti`, `Td`;<br>Step-transition and stop-priority rules;<br>PID saturation and integration-suspension rules;<br>Discharge-opening setting `40%` | Fill-valve register command `FillValve` at `%QW100`;<br>Discharge-valve register command `DischargeValve` at `%QW101` | OpenPLC Runtime;<br>PLC scan clock and state memory;<br>Modbus TCP connection;<br>Factory I/O slave driver with Scale = 100 |
| **A1** | **Acquire commands and scale level** | Start-command signal `StartCommand`;<br>Stop-command signal `StopCommand`;<br>Level-meter register value `LevelMeter` | I/O mapping specification;<br>Analog scaling specification;<br>`FULL_SCALE`;<br>`h_span`;<br>Rising-edge detection rule | `start`;<br>`stop`;<br>Measured level `h` | OpenPLC input image;<br>Modbus TCP input transfer;<br>Previous-command memory |
| **A2** | **Evaluate level conditions and settling** | Measured level `h`;<br>Regulation-active status | `h_sp`;<br>`h_target`;<br>`h_max`;<br>`eps`;<br>`t_h`;<br>Continuous-dwell and timer-reset rules | Level error `e`;<br>`r`;<br>`settled` | PLC arithmetic facilities;<br>Scan clock;<br>Dwell-timer state |
| **A3** | **Manage regulation steps** | `start`;<br>`stop`;<br>`r`;<br>`settled` | Initial-step rule;<br>Stop-priority rule;<br>Start-transition rule;<br>Regulation-completion rule;<br>Inactive-output rule | Step state;<br>Regulation-active status;<br>`fill_valve`;<br>`discharge_valve` | PLC sequence logic;<br>Step-state memory |
| **A4** | **Calculate bounded PID demand** | Level error `e`;<br>`fill_valve` | PID parameters `Kp`, `Ti`, `Td`;<br>PID execution interval;<br>Demand limits `0–100%`;<br>Integration-suspension rule;<br>Inactive-controller rule | Bounded fill-opening demand | PLC PID calculation facilities;<br>PID state memory;<br>Scan clock |
| **A5** | **Generate analog valve commands** | Bounded fill-opening demand;<br>`fill_valve`;<br>`discharge_valve` | Output-address mapping;<br>`FULL_SCALE`;<br>Discharge-opening setting `40%`;<br>Zero-output rule;<br>Integer-conversion and output-range rules | Fill-valve register command `FillValve` at `%QW100`;<br>Discharge-valve register command `DischargeValve` at `%QW101` | OpenPLC output image;<br>Modbus TCP output transfer;<br>Factory I/O slave driver |

## Child-function connections

These connections define the internal arrows of the A0 decomposition.

| Source | Arrow | Destination |
|---|---|---|
| A0 input boundary | Start-command signal `StartCommand`; Stop-command signal `StopCommand`; Level-meter register value `LevelMeter` | A1 |
| A1 | Measured level `h` | A2 |
| A1 | `start`; `stop` | A3 |
| A2 | `r`; `settled` | A3 |
| A2 | Level error `e` | A4 |
| A3 | Regulation-active status | A2 |
| A3 | `fill_valve` | A4 and A5 |
| A3 | `discharge_valve` | A5 |
| A4 | Bounded fill-opening demand | A5 |
| A5 | Fill-valve register command `FillValve`; Discharge-valve register command `DischargeValve` | A0 output boundary |

A0 controls are distributed to the applicable child functions as shown in the ICOM table. A0 mechanisms provide the execution and communication resources for those functions. **Step state** is an internal sequence-status output retained by A3.

## Arrow semantics and governing rules

### A1 — Command and measurement interpretation

- `start` is the rising-edge event of `StartCommand`, TRUE only during the scan in which a press is detected.
- `stop` is the current Boolean value of `StopCommand`.
- Measured level:
  \[
  h=\frac{\text{LevelMeter}}{\text{FULL\_SCALE}}\,h_{\text{span}}
  \]
- Thus the nominal target, overfill limit, and tolerance correspond to register values **800**, **900**, and **20**, respectively.

### A2 — Level classification and dwell qualification

\[
e=h_{sp}-h
\]

| Arrow | Meaning |
|---|---|
| `r = LOW` | \(h<h_{target}\) |
| `r = MID` | \(h_{target}\le h<h_{max}\) |
| `r = HIGH` | \(h\ge h_{max}\) |
| `settled` | Regulation is active and \(\lvert e\rvert\le eps\) has remained continuously true for at least \(t_h=10\,s\) |

The dwell timer resets whenever regulation is inactive or the level leaves the tolerance band. Separate visits to the band do not accumulate.

### A3 — Step supervision

| Current condition | Resulting step | `fill_valve` | `discharge_valve` |
|---|---:|---:|---:|
| Initialization | 0 | FALSE | FALSE |
| `stop = TRUE`, from any step | 0 | FALSE | FALSE |
| Step 0, `start = FALSE` | 0 | FALSE | FALSE |
| Step 0, `start = TRUE`, `stop = FALSE`, and `r ≠ HIGH` | Regulation step | TRUE | TRUE |
| Regulation step, `stop = FALSE`, `settled = FALSE`, and `r ≠ HIGH` | Regulation step | TRUE | TRUE |
| Regulation step, `settled = TRUE` or `r = HIGH` | 0 | FALSE | FALSE |
| Step 0, `start = TRUE`, and `r = HIGH` | 0 | FALSE | FALSE |

**Stop has highest priority.** The overfill condition prevents valve activation even when a start event occurs in the same scan. A start event during regulation does not restart the sequence or reset the dwell timer. A new button press is required after completion.

“Step 0 drives no output” is interpreted as **both physical analog commands being zero**, not as retaining their previous values.

### A4 — PID demand generation

While `fill_valve = TRUE`:

- Compute PID demand from \(e=h_{sp}-h\).
- Clamp the applied demand to **0–100%**.
- Suspend integration whenever the unconstrained demand is outside those limits and therefore requires clamping.

While `fill_valve = FALSE`, the effective demand is zero and integration is suspended. PID initialization and derivative-history handling must be defined before implementation; the task does not prescribe a particular restart policy.

### A5 — Physical output generation

Let \(u\) be the bounded fill-opening demand expressed as a fraction from 0 to 1.

| Logical condition | Physical command |
|---|---|
| `fill_valve = TRUE` | `FillValve` = integer representation of \(u \times 1000\), constrained to 0–1000 |
| `fill_valve = FALSE` | `FillValve = 0` |
| `discharge_valve = TRUE` | `DischargeValve = 400` |
| `discharge_valve = FALSE` | `DischargeValve = 0` |

`fill_valve = TRUE` means the PID is enabled to drive the fill valve; it does **not** imply a nonzero opening, since the bounded PID demand may be zero.

The scan execution must propagate A3’s stop or completion decision to A5 **before the output image is committed**, ensuring both valves close in the scan that recognizes the terminating condition.
