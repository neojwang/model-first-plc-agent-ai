## A0 — Regulate the tank level

The model below uses **A0** for the requested context function and **A1–A5** for its decomposition. In conventional FIPS 183 diagram numbering, the single-box context diagram is **A-0**, and its decomposition diagram is **A0**.

**Boundary:** the control function runs in OpenPLC. The Factory I/O tank is the external plant; its measurements and commands cross the model boundary through the mapped I/O.

### A0 context ICOM

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| A0 | Regulate the tank level | StartCommand signal `%IX100.0`; StopCommand signal `%IX100.1`; LevelMeter register `%IW100` | Level-control requirements; I/O mapping; `FULL_SCALE = 1000`; measuring span `h_span`; target `h_sp = h_target = 0.8 h_span`; overfill limit `h_max = 0.9 h_span`; tolerance `eps = 0.02 h_span`; hold time `t_h = 10 s`; PID parameters `Kp`, `Ti`, `Td`; PLC scan period | FillValve register `%QW100`; DischargeValve register `%QW101` | OpenPLC Runtime; Modbus TCP connection; Factory I/O slave interface with driver Scale = 100; PLC timing and retained scan-to-scan memory |

## A0 decomposition

Every function name is a verb phrase. Arrow labels below are noun phrases; the required identifier vocabulary is retained exactly.

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| A1 | Acquire commands and scale the level | StartCommand signal; StopCommand signal; LevelMeter register | I/O mapping; `FULL_SCALE`; measuring span `h_span`; rising-edge definition of `start`; initial edge-memory condition | `start`; `stop`; measured level `h` | PLC input image; Modbus TCP interface; edge-detection memory; scaling arithmetic |
| A2 | Evaluate level conditions and qualify settling | Measured level `h` | Target `h_sp = h_target`; limit `h_max`; tolerance `eps`; hold time `t_h`; regulation state; PLC scan period; settling-timer reset rules | Level error `e`; level region `r`; `settled` | Comparison and arithmetic operations; non-retentive on-delay timer |
| A3 | Select the regulation state | `start`; `stop`; `settled`; level region `r` | Initial-state rule; stop priority; regulation-completion rule; start-event acceptance rule | Regulation state; `fill_valve`; `discharge_valve` | State memory; PLC cyclic execution |
| A4 | Calculate the bounded PID demand | Level error `e` | `fill_valve`; PID parameters `Kp`, `Ti`, `Td`; PLC scan period; output bounds of 0–100%; integration-suspension rule; PID initialization rule | Bounded fill demand | PID calculation facility; integral and derivative memory |
| A5 | Apply the valve commands | Bounded fill demand | `fill_valve`; `discharge_valve`; `stop`; `FULL_SCALE`; discharge-opening constant of 40%; zero-output priority; integer-conversion rule | FillValve register `%QW100`; DischargeValve register `%QW101` | PLC output image; Modbus TCP interface; Factory I/O slave interface |

### Internal arrow connections

These connections make the decomposition explicit and preserve the A0 boundary.

| Arrow | Source | Destination |
|---|---|---|
| StartCommand signal; StopCommand signal; LevelMeter register | A0 inputs | A1 inputs |
| `start`; `stop` | A1 outputs | A3 inputs |
| `stop` | A1 output | A5 control |
| Measured level `h` | A1 output | A2 input |
| Level error `e` | A2 output | A4 input |
| Level region `r`; `settled` | A2 outputs | A3 inputs |
| Regulation state | A3 output | A2 control |
| `fill_valve` | A3 output | A4 and A5 controls |
| `discharge_valve` | A3 output | A5 control |
| Bounded fill demand | A4 output | A5 input |
| FillValve register; DischargeValve register | A5 outputs | A0 outputs |

The context controls and mechanisms are allocated to the child functions as shown in the ICOM table. Internal state, timing, and PID feedback remain inside A0.

## Functional rules

### A1 — Acquire commands and scale the level

- `start` is TRUE for exactly one scan on a FALSE-to-TRUE transition of StartCommand. Holding the button does not create repeated start events.
- `stop` follows StopCommand as a level-sensitive signal.
- Level scaling is:

\[
h=\frac{\text{LevelMeter}}{\text{FULL\_SCALE}}\,h_{\text{span}}
\]

Thus, in register-equivalent units, the target is **800**, the overfill limit is **900**, and the tolerance is **20**.

### A2 — Evaluate level conditions and qualify settling

\[
e=h_{sp}-h
\]

| Identifier | Meaning |
|---|---|
| `r = LOW` | \(h<h_{target}\) |
| `r = MID` | \(h_{target}\le h<h_{max}\) |
| `r = HIGH` | \(h\ge h_{max}\) |
| `settled` | \(\lvert e\rvert\le eps\) continuously for at least \(t_h=10\,s\) during regulation |

The settling timer resets whenever the level leaves the tolerance band or regulation is inactive. Time accumulated before a new regulation cycle does not count toward that cycle.

### A3 — Select the regulation state

There are two states: **step 0**, initially active, and **regulation**.

| Priority | Present state | Condition | Resulting state |
|---|---|---|---|
| 1 — highest | Any state | `stop` | Step 0 |
| 2 | Regulation | `settled` or `r = HIGH` | Step 0 |
| 3 | Step 0 | `start` and not `stop` and `r ≠ HIGH` | Regulation |
| 4 | Any state | No applicable condition above | Present state |

The high-level guard on entry prevents an actuation pulse when a start event occurs at or above the overfill limit.

| Regulation state | `fill_valve` | `discharge_valve` |
|---|---|---|
| Step 0 | FALSE | FALSE |
| Regulation | TRUE | TRUE |

These Boolean identifiers are **mode enables**, not analog valve positions. In particular, `fill_valve` may be TRUE while the bounded PID demand is zero.

A `start` event during regulation is ignored; it is not queued for a later cycle.

### A4 — Calculate the bounded PID demand

While `fill_valve` is TRUE:

- Calculate PID action using \(e=h_{sp}-h\) and `Kp`, `Ti`, `Td`.
- Clamp the fill demand to **0–100%**.
- Suspend integral accumulation while the PID output is clamped.
- Continue evaluating the controller so that it can leave saturation when conditions permit.

While inactive, the PID does not accumulate integral action. Its integral and derivative histories are initialized for each new regulation cycle so that stale values from a previous cycle are not reused. The particular discrete PID realization remains an implementation choice.

### A5 — Apply the valve commands

With bounded fill demand \(u\) expressed as a fraction from 0 to 1:

| Condition | FillValve `%QW100` | DischargeValve `%QW101` |
|---|---:|---:|
| `stop` is TRUE, or step 0 is active | 0 | 0 |
| Regulation is active | Integer-converted \(u\times1000\), bounded to 0–1000 | 400 |

**Step 0 therefore has no active output actions; the output-mapping function explicitly writes both valve commands to zero.** Completion and stop decisions affect both outputs in the same control scan.
