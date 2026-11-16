## A0 context and decomposition

**A0 — Control timed tank filling**

**Purpose:** Fill the tank in timed phases separated by timed pauses, terminate filling at LSH, and return to the initial state on StopCommand.

**Boundary:** The model includes input conditioning, supervisory decisions, step sequencing, timer evaluation, and output commanding. The simulated tank, valves, and level switches form the external plant.

### Modeling conventions

- **Inputs** are information transformed by a function.
- **Controls** are rules, constraints, or settings governing a function.
- **Outputs** are the results of a function.
- **Mechanisms** are the resources performing a function.
- All function names below are verb phrases. Arrow names are noun phrases.
- **Step 0**, **Filling step**, and **Pause step** are mutually exclusive states.
- The specified identifiers `start`, `stop`, `LSH`, `LSHH`, `ton_q`, `tof_q`, `fill_valve`, and `discharge_valve` are preserved.

### ICOM table

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control timed tank filling** | Raw command states; Raw level-switch states | Timed-filling requirements; TON_Duration; TOF_Duration; Initial-state rule; Stop-priority rule; High-level protection rule; I/O address map | Valve command vector (`fill_valve`, `discharge_valve`) | OpenPLC Runtime; PLC cyclic execution; Modbus TCP connection; Factory I/O slave device |
| **A1** | **Acquire and condition plant signals** | Raw command states; Raw level-switch states | I/O address map; Rising-edge definition for `start`; Input sampling rules | Conditioned signal vector (`start`, `stop`, `LSH`, `LSHH`) | OpenPLC input image; Modbus TCP connection; Factory I/O input tags; StartCommand edge memory |
| **A2** | **Determine filling permission and reset demand** | Conditioned signal vector (`start`, `stop`, `LSH`, `LSHH`) | Stop-priority rule; LSH completion rule; LSHH protective-inhibit rule | Filling permission; Step-0 reset demand | OpenPLC Boolean evaluation |
| **A3** | **Sequence filling and pause steps** | Conditioned signal vector (`start`, `stop`, `LSH`, `LSHH`); Timer status vector (`ton_q`, `tof_q`); Filling permission; Step-0 reset demand | Initial-state rule; State-transition rules; Mutually exclusive step rule; Reset-priority rule | Active-step state; Filling-step activity | OpenPLC state memory; PLC cyclic execution |
| **A4** | **Evaluate filling and pause timers** | Filling-step activity | TON_Duration; TOF_Duration; TON behavior; TOF behavior; Timer initialization rules | Timer status vector (`ton_q`, `tof_q`) | OpenPLC TON instance; OpenPLC TOF instance; Runtime time base |
| **A5** | **Command tank valves** | Active-step state; Filling permission; Step-0 reset demand | Valve-command rules; Discharge-valve prohibition; I/O address map | Valve command vector (`fill_valve`, `discharge_valve`) | OpenPLC output image; Modbus TCP connection; Factory I/O valve tags |

## Child-function connectivity

The following connections define the internal arrows of the A0 decomposition.

| Arrow name | Source | Destination |
|---|---|---|
| Raw command states | A0 input boundary | A1 |
| Raw level-switch states | A0 input boundary | A1 |
| Conditioned signal vector (`start`, `stop`, `LSH`, `LSHH`) | A1 | A2, A3 |
| Filling permission | A2 | A3, A5 |
| Step-0 reset demand | A2 | A3, A5 |
| Filling-step activity | A3 | A4 |
| Timer status vector (`ton_q`, `tof_q`) | A4 | A3 |
| Active-step state | A3 | A5 |
| Valve command vector (`fill_valve`, `discharge_valve`) | A5 | A0 output boundary |

The A3–A4 feedback represents state-dependent timing. IDEF0 describes functional dependencies; it does not prescribe PLC instruction order.

## Signal and address definitions

| Arrow member or boundary signal | Meaning | Physical mapping |
|---|---|---|
| Raw StartCommand state | Sampled start-button state | `StartCommand AT %IX100.0 : BOOL` |
| Raw StopCommand state | Sampled stop-button state | `StopCommand AT %IX100.1 : BOOL` |
| `start` | One-scan rising-edge event derived from StartCommand | Derived signal; no separate physical address |
| `stop` | Current StopCommand state | `%IX100.1` |
| `LSH` | High-level switch state at 2.4 m | `LSH AT %IX100.2 : BOOL` |
| `LSHH` | High-high-level switch state at 2.7 m | `LSHH AT %IX100.3 : BOOL` |
| `ton_q` | TON output Q | Internal timer status |
| `tof_q` | TOF output Q | Internal timer status |
| `fill_valve` | Fill-valve command | `FillValve AT %QX100.0 : BOOL` |
| `discharge_valve` | Discharge-valve command, always FALSE | `DischargeValve AT %QX100.1 : BOOL` |

## Governing controls

### Supervisory rules

A2 produces:

- **Filling permission:** present only when `stop`, `LSH`, and `LSHH` are all FALSE.
- **Step-0 reset demand:** present whenever `stop`, `LSH`, or `LSHH` is TRUE.

Thus, a level or stop condition prevents even a momentary start of filling. Reset demand takes priority over every normal transition.

**LSHH interpretation:** The requirement that LSHH must never be reached is modeled as a safety constraint, with an additional protective inhibit if `LSHH` is detected. Normal termination remains at LSH. No alarm latch or manual fault-reset behavior is assumed.

### State-transition rules

| Current state | Condition | Next state |
|---|---|---|
| Any state | `stop` is TRUE | Step 0 |
| Any state | `LSH` or `LSHH` is TRUE | Step 0 |
| Step 0 | `start` is TRUE and filling permission is present | Filling step |
| Filling step | `ton_q` is TRUE and filling permission is present | Pause step |
| Pause step | `tof_q` is FALSE and filling permission is present | Filling step |
| Any state | No applicable transition condition | Current state |

The rows are evaluated with the stated reset priority. A held StartCommand does not repeatedly start the process: only its rising-edge event produces `start`.

### Timer rules

| Timer | Input activity | Time setting | Required behavior |
|---|---|---|---|
| TON | Filling-step activity | TON_Duration | `ton_q` becomes TRUE after continuous filling-step activity for TON_Duration. Leaving the filling step resets the TON. |
| TOF | Filling-step activity | TOF_Duration | `tof_q` is TRUE during filling and remains TRUE for TOF_Duration after the filling step is left. Its subsequent FALSE state permits resumption from the Pause step. |

Both timers have initialized, non-retentive state. The TOF may remain TRUE temporarily after a stop or level-completion event, but that status cannot open the valve or leave Step 0 without a new valid `start`.

### Valve-command rules

| Operating condition | `fill_valve` | `discharge_valve` |
|---|---:|---:|
| Step 0 | FALSE | FALSE |
| Filling step with filling permission | TRUE | FALSE |
| Pause step | FALSE | FALSE |
| Step-0 reset demand | FALSE | FALSE |

**Physical safety qualification:** Preventing the actual liquid level from reaching 2.7 m also requires adequate margin between LSH and LSHH for input sampling, communications, valve closure, and residual inflow. The logical model alone cannot guarantee that physical margin; it must be validated against the plant dynamics.
