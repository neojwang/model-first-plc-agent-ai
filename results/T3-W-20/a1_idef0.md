## 1. Model scope and interpretation

The model controls intermittent filling using three steps:

- **Step 0 — Idle:** initial step; both valves closed.
- **Step 1 — Filling:** fill valve open; TON and TOF inputs active.
- **Step 2 — Pausing:** both valves closed; filling resumes after the TOF output becomes FALSE.

The following interpretations make the behavior deterministic:

- `start` is a rising-edge event, not the maintained state of the Start button.
- `stop` has priority over all other receptivities.
- `LSH` terminates filling from either active step and prevents starting while already asserted.
- `LSHH` is treated as an additional protective shutdown and start inhibition. This is a conservative design provision supporting the requirement that LSHH must never be reached.
- Returning to Step 0 does not automatically restart filling. A new `start` event is required.

## 2. A0 context function

**A0 — Control timed tank filling**

The function receives operator commands and tank-level indications, applies the sequence and timing requirements, and produces valve commands.

### ICOM model

Arrow labels below are noun phrases; function names are verb phrases. Parenthesized identifiers identify the corresponding signal or parameter.

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control timed tank filling** | Start-command signal (`StartCommand`); stop-command signal (`StopCommand`); high-level indication (`LSH`); high-high-level indication (`LSHH`) | Filling-duration parameter (`TON_Duration`); pause-duration parameter (`TOF_Duration`); initial-step requirement; sequence-transition rules; stop-priority rule; level-protection rules; discharge-closure requirement; I/O address mapping | Fill-valve command (`fill_valve`); discharge-valve command (`discharge_valve`) | OpenPLC Runtime; PLC execution and memory resources; TON and TOF timer resources; Modbus TCP connection; Factory I/O tank scene |

## 3. A0 decomposition

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|---|
| **A1** | **Acquire commands and level indications** | Start-command signal (`StartCommand`); stop-command signal (`StopCommand`); high-level indication (`LSH`); high-high-level indication (`LSHH`) | Input address mapping; rising-edge definition; scan-sampling rules | Start event (`start`); stop state (`stop`); high-level state (`LSH`); high-high-level state (`LSHH`) | OpenPLC input image; Modbus TCP input exchange; rising-edge memory |
| **A2** | **Determine the active sequence step** | Start event (`start`); stop state (`stop`); high-level state (`LSH`); high-high-level state (`LSHH`); on-delay completion state (`ton_q`); off-delay output state (`tof_q`) | Initial-step requirement; transition rules; stop-priority rule; level-protection rules; current-step state | Updated-step state; filling-step activity | OpenPLC scan execution; sequence-state memory |
| **A3** | **Evaluate filling and pause timing** | Filling-step activity | Filling-duration parameter (`TON_Duration`); pause-duration parameter (`TOF_Duration`); TON timing semantics; TOF timing semantics; timer initialization rules | On-delay completion state (`ton_q`); off-delay output state (`tof_q`) | TON timer instance; TOF timer instance; runtime time base; timer-instance memory |
| **A4** | **Generate valve commands** | Updated-step state; stop state (`stop`); high-level state (`LSH`); high-high-level state (`LSHH`) | Step-output assignments; stop-priority rule; level-protection rules; discharge-closure requirement; output address mapping | Fill-valve command (`fill_valve`); discharge-valve command (`discharge_valve`) | OpenPLC output image; Modbus TCP output exchange; Factory I/O valve actuators |

### Internal arrow connections

These connections preserve the A0 boundary and make the child-function dependencies explicit.

| Arrow name | Source | Destination |
|---|---|---|
| Start-command signal | A0 input boundary | A1 |
| Stop-command signal | A0 input boundary | A1 |
| High-level indication | A0 input boundary | A1 |
| High-high-level indication | A0 input boundary | A1 |
| Start event (`start`) | A1 | A2 |
| Stop state (`stop`) | A1 | A2, A4 |
| High-level state (`LSH`) | A1 | A2, A4 |
| High-high-level state (`LSHH`) | A1 | A2, A4 |
| Filling-step activity | A2 | A3 |
| On-delay completion state (`ton_q`) | A3 | A2 |
| Off-delay output state (`tof_q`) | A3 | A2 |
| Updated-step state | A2 | A4 |
| Fill-valve command (`fill_valve`) | A4 | A0 output boundary |
| Discharge-valve command (`discharge_valve`) | A4 | A0 output boundary |

The A2–A3 connections represent stateful feedback, not an execution-order diagram. During PLC implementation, timer evaluation and step updates must have a documented scan order so that these transitions remain deterministic.

## 4. Sequence controls for A2

The receptivities below use only the specified identifier vocabulary. Apply the global priority rules before the step-specific rules.

### Global priority rules

| Priority | Applicable steps | Receptivity | Result |
|---|---|---|---|
| 1 | All steps | `stop` | Select Step 0; both outputs FALSE |
| 2 | All steps | `LSHH` | Select Step 0; both outputs FALSE |
| 3 | All steps | `LSH` | Select or retain Step 0; both outputs FALSE |

### Step-specific rules

These rules apply only when none of the global priority receptivities is TRUE.

| Current step | Receptivity | Next step |
|---|---|---|
| Step 0 — Idle | `start` | Step 1 — Filling |
| Step 1 — Filling | `ton_q AND NOT LSH` | Step 2 — Pausing |
| Step 2 — Pausing | `NOT tof_q` | Step 1 — Filling |

In the absence of an applicable transition, retain the current step. A `start` event during Filling or Pausing has no effect.

## 5. Timing controls for A3

| Timer | Input activity | Preset control | Output arrow | Required behavior |
|---|---|---|---|---|
| TON | Filling-step activity | `TON_Duration` | On-delay completion state (`ton_q`) | Becomes TRUE after continuous filling-step activity for the preset duration; resets when filling-step activity becomes FALSE |
| TOF | Filling-step activity | `TOF_Duration` | Off-delay output state (`tof_q`) | Is TRUE during filling; remains TRUE for the preset duration after filling-step activity becomes FALSE; then becomes FALSE |

Both timer instances must be evaluated continuously, including outside Step 1.

On a normal Filling-to-Pausing transition:

1. Filling-step activity becomes FALSE.
2. TON resets.
3. TOF retains `tof_q` TRUE for `TOF_Duration`.
4. Pausing continues until `tof_q` is FALSE.
5. Filling resumes, starting a fresh TON interval.

A residual TRUE `tof_q` after a stop or level shutdown cannot restart the sequence from Step 0.

## 6. Output controls for A4

| Selected step | `fill_valve` | `discharge_valve` |
|---|---:|---:|
| Step 0 — Idle | FALSE | FALSE |
| Step 1 — Filling | TRUE | FALSE |
| Step 2 — Pausing | FALSE | FALSE |

Regardless of the selected step, `stop`, `LSH`, or `LSHH` forces both outputs FALSE. The TOF output is a **pause-transition condition**, not a valve command: it must not hold the fill valve open after Step 1 is left.

### Boundary I/O mapping

| Physical tag | Address | Model identifier |
|---|---|---|
| `StartCommand` | `%IX100.0` | `start`, after rising-edge detection |
| `StopCommand` | `%IX100.1` | `stop` |
| `LSH` | `%IX100.2` | `LSH` |
| `LSHH` | `%IX100.3` | `LSHH` |
| `FillValve` | `%QX100.0` | `fill_valve` |
| `DischargeValve` | `%QX100.1` | `discharge_valve` |

## 7. Plant constraint requiring validation

**“LSHH must never be reached” cannot be guaranteed by the logical model alone.** LSH is at 2.4 m and LSHH at 2.7 m, leaving a 0.3 m margin. Validation must show that level rise during input sampling, communications, PLC execution, valve closure, and residual inflow remains below that margin.

The `LSHH` shutdown is a fallback response to a violated limit; it is not proof that the limit cannot be reached.
