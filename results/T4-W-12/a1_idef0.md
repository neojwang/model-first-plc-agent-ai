## A0 context model — Control the tank level

**Scope:** Control the Factory I/O tank through the OpenPLC Runtime and its Modbus TCP connection. The model covers input interpretation, sequence supervision, PID regulation, settling detection, and analog output generation.

The tables use the requested **A0 context / A1–A5 child** numbering. In conventional FIPS 183 diagram numbering, the single-box context diagram is **A-0**, and its decomposition diagram is **A0**.

### Arrow definitions

All arrow labels below are noun phrases. The required identifiers retain their exact spelling.

| Arrow name | Meaning |
|---|---|
| **StartCommand signal** | Boolean input at `%IX100.0`. |
| **StopCommand signal** | Boolean input at `%IX100.1`. |
| **LevelMeter value** | Integer input at `%IW100`, proportional to the level-meter voltage. |
| **Signal conversion specification** | Rising-edge interpretation of StartCommand; direct interpretation of StopCommand; level scaling using `FULL_SCALE = 1000`, corresponding to 10 V and `h_span`. |
| **Regulation parameters** | `h_sp = h_target = 0.8 h_span`; `h_max = 0.9 h_span`; `eps = 0.02 h_span`; `t_h = 10 s`. |
| **Sequence rules** | Initial step 0; start-event transition; stop priority; completion conditions; idle and regulation output permissions. |
| **PID configuration** | Gains `Kp`, `Ti`, `Td`; PID execution interval; output limits of 0–100%; integration suspension while the output is clamped. |
| **Output mapping specification** | Fill demand conversion to `%QW100`; fixed discharge demand of `0.4 FULL_SCALE = 400` at `%QW101`; zero commands whenever the respective enable is FALSE. |
| **start** | StartCommand rising-edge event, TRUE only during the scan in which the button is pressed. |
| **stop** | Current Boolean StopCommand condition. |
| **Measured level h** | Level measurement expressed in the same units as `h_span`. |
| **Level error e** | `h_sp − h`. |
| **r** | Level region: LOW, MID, or HIGH. |
| **settled** | Condition indicating that `abs(e) <= eps` has held continuously for `t_h` during regulation. |
| **Regulation status** | Current sequence condition: step 0 or regulation. |
| **fill_valve** | Boolean permission for PID control of the fill valve. |
| **discharge_valve** | Boolean permission for the fixed 40% discharge opening. |
| **Limited PID demand** | PID fill demand clamped to 0–100% opening. |
| **FillValve command** | Integer analog command at `%QW100`. |
| **DischargeValve command** | Integer analog command at `%QW101`. |

## ICOM table

Controls specify the conditions or rules governing a function. Mechanisms identify the resources that perform it.

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control the tank level** | StartCommand signal; StopCommand signal; LevelMeter value | Signal conversion specification; Regulation parameters; Sequence rules; PID configuration; Output mapping specification | FillValve command; DischargeValve command | OpenPLC Runtime; PLC task scheduler; Modbus TCP connection; Factory I/O analog Level Control scene |
| **A1** | **Interpret the command and measurement signals** | StartCommand signal; StopCommand signal; LevelMeter value | Signal conversion specification | start; stop; Measured level h | OpenPLC input image; edge-detection memory; numeric conversion facilities |
| **A2** | **Evaluate the level and settling conditions** | Measured level h | Regulation parameters; Regulation status | Level error e; r; settled | PLC arithmetic and comparison facilities; nonretentive timer; PLC time base |
| **A3** | **Supervise the regulation sequence** | start; stop; r; settled | Sequence rules | Regulation status; fill_valve; discharge_valve | PLC sequence-state memory; PLC task scheduler |
| **A4** | **Calculate the limited PID demand** | Level error e | PID configuration; fill_valve | Limited PID demand | PID calculation facilities; PID state memory; PLC time base |
| **A5** | **Generate the analog valve commands** | Limited PID demand | fill_valve; discharge_valve; Output mapping specification | FillValve command; DischargeValve command | Numeric conversion facilities; OpenPLC output image; Modbus TCP connection |

## Child-function connections

These connections define the internal arrows of the A0 decomposition.

| Source | Arrow | Destination and ICOM role |
|---|---|---|
| A0 input boundary | StartCommand signal; StopCommand signal; LevelMeter value | A1 inputs |
| A1 | start; stop | A3 inputs |
| A1 | Measured level h | A2 input |
| A2 | Level error e | A4 input |
| A2 | r; settled | A3 inputs |
| A3 | Regulation status | A2 control |
| A3 | fill_valve | A4 control; A5 control |
| A3 | discharge_valve | A5 control |
| A4 | Limited PID demand | A5 input |
| A5 | FillValve command; DischargeValve command | A0 output boundary |

The five specification and parameter arrows enter from the A0 control boundary and connect to the child functions shown in the ICOM table. The A0 mechanisms support the child mechanisms listed there.

## Functional rules

### A1 — Interpret the command and measurement signals

- Generate **start** from the rising edge of StartCommand, not from its sustained TRUE level.
- Set **stop** equal to StopCommand.
- Convert the level measurement using:

  \[
  h=\frac{\text{LevelMeter}}{\text{FULL\_SCALE}}h_{\text{span}}
  \]

  Therefore, the nominal register equivalents are:
  - Target: **800**
  - Overfill limit: **900**
  - Tolerance: **20**

### A2 — Evaluate the level and settling conditions

Calculate:

\[
e=h_{sp}-h
\]

Assign **r** as follows:

| Condition | r |
|---|---|
| `h < h_target` | LOW |
| `h_target <= h < h_max` | MID |
| `h >= h_max` | HIGH |

Generate **settled** only after `abs(e) <= eps` has remained continuously TRUE for 10 s **during regulation**. Reset the timing accumulation whenever regulation is inactive or the error leaves the tolerance band.

### A3 — Supervise the regulation sequence

| Current condition | Receptivity | Resulting condition | fill_valve | discharge_valve |
|---|---|---|---|---|
| Any condition | `stop` | Step 0 | FALSE | FALSE |
| Step 0 | No `start` | Step 0 | FALSE | FALSE |
| Step 0 | `start AND NOT stop AND r <> HIGH` | Regulation | TRUE | TRUE |
| Step 0 | `start AND r = HIGH` | Step 0 | FALSE | FALSE |
| Regulation | `NOT stop AND NOT settled AND r <> HIGH` | Regulation | TRUE | TRUE |
| Regulation | `settled OR r = HIGH` | Step 0 | FALSE | FALSE |

**Priority:** `stop` dominates all other conditions. Completion and overfill conditions suppress valve permissions without an additional scan of actuation. After completion or stopping, a fresh **start** event is required; holding StartCommand does not restart regulation.

### A4 — Calculate the limited PID demand

While **fill_valve** is TRUE:

- Calculate the PID demand from **Level error e**.
- Clamp the demand to **0–100%**.
- Suspend integration while the output is clamped.

While **fill_valve** is FALSE, the PID cannot actuate the fill valve, and inactive time must not accumulate integral action. The task does not specify whether PID state is reset or retained between runs; that policy should be resolved during detailed design.

### A5 — Generate the analog valve commands

| Permission | Output command |
|---|---|
| `fill_valve = TRUE` | FillValve command = Limited PID demand scaled to **0–1000** |
| `fill_valve = FALSE` | FillValve command = **0** |
| `discharge_valve = TRUE` | DischargeValve command = **400** |
| `discharge_valve = FALSE` | DischargeValve command = **0** |

Thus, **step 0 drives no valve opening**: both analog commands are explicitly zero rather than left at their previous values.
