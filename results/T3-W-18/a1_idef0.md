## A0 context model — Control timed tank filling

The model uses **Step 0 (idle)**, a **filling step**, and a **pause step**. No PLC code is defined here.

**Modeling conventions**
- Inputs are information transformed by a function; controls constrain its behavior; outputs are its results; mechanisms perform the function.
- Arrow labels are noun phrases or the exact identifiers required by the task.
- The parent node **A0** is decomposed into **A1–A4** below.
- `start` is a one-scan rising-edge event, not the maintained value of `StartCommand`.

### Context ICOM

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| A0 | Control timed tank filling | `StartCommand`; `StopCommand`; `LSH`; `LSHH` | `TON_Duration`; `TOF_Duration`; initial-step requirement; stop-priority requirement; timed filling and pause rules; high-level termination requirement; high-high-level avoidance requirement; discharge-inhibition requirement; I/O address mapping | `fill_valve`; `discharge_valve` | OpenPLC Runtime; PLC cyclic task; Modbus TCP connection; Factory I/O digital tank plant; fill-valve actuator; level switches |

### Interface mapping

These are interface annotations, not additional receptivity or output identifiers.

| Model identifier | Plant/runtime interface | Meaning |
|---|---|---|
| `start` | Rising edge of `StartCommand AT %IX100.0` | Start-button press event |
| `stop` | `StopCommand AT %IX100.1` | Stop request |
| `LSH` | `LSH AT %IX100.2` | Level detection at 2.4 m |
| `LSHH` | `LSHH AT %IX100.3` | Level detection at 2.7 m |
| `fill_valve` | `FillValve AT %QX100.0` | Fill-valve command |
| `discharge_valve` | `DischargeValve AT %QX100.1` | Discharge-valve command, always FALSE |
| `ton_q` | TON output Q | Filling-duration completion indication |
| `tof_q` | TOF output Q | Filling-activity/off-delay indication |

The Factory I/O scene is the Modbus TCP slave device; its tags must be mapped to the specified addresses.

## A0 decomposition

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| A1 | Acquire commands and level indications | `StartCommand`; `StopCommand`; `LSH`; `LSHH` | I/O address mapping; rising-edge detection rule; initial edge-memory convention | `start`; `stop`; `LSH`; `LSHH` | OpenPLC input image; Modbus TCP driver; rising-edge detector; previous-command memory |
| A2 | Manage filling steps | `start`; `stop`; `LSH`; `LSHH`; `ton_q`; `tof_q` | Initial-step requirement; transition rules; stop priority; level-termination priority; high-high-level interlock policy | Step-state record; filling-step activity | PLC cyclic task; sequence-state memory |
| A3 | Evaluate filling and pause delays | Filling-step activity | `TON_Duration`; `TOF_Duration`; TON semantics; TOF semantics; timer initialization rules | `ton_q`; `tof_q` | TON function-block instance; TOF function-block instance; runtime time base; timer-instance memory |
| A4 | Apply valve commands | Step-state record | `stop`; `LSH`; `LSHH`; fill-enable rule; discharge-inhibition requirement; output address mapping | `fill_valve`; `discharge_valve` | OpenPLC output image; Modbus TCP driver; fill-valve actuator; discharge-valve actuator |

### Internal arrow connections

| Arrow | Source | Destination |
|---|---|---|
| `start` | A1 | A2 input |
| `stop` | A1 | A2 input; A4 control |
| `LSH` | A1 | A2 input; A4 control |
| `LSHH` | A1 | A2 input; A4 control |
| Step-state record | A2 | A4 input |
| Filling-step activity | A2 | A3 input |
| `ton_q` | A3 | A2 input |
| `tof_q` | A3 | A2 input |
| `fill_valve` | A4 | A0 output boundary |
| `discharge_valve` | A4 | A0 output boundary |

The A2–A3 feedback represents the sequence/timer interaction. It is not an instruction-execution order; scan-consistent evaluation must be established during implementation.

## Behavioral controls

### Step definitions

| Step | Function | Filling-step activity | Output behavior |
|---|---|---:|---|
| Step 0 | Await a start event | FALSE | `fill_valve` = FALSE; `discharge_valve` = FALSE |
| Filling step | Admit liquid | TRUE | `fill_valve` enabled subject to the stop and level interlocks; `discharge_valve` = FALSE |
| Pause step | Suspend liquid admission | FALSE | `fill_valve` = FALSE; `discharge_valve` = FALSE |

### Transition rules

Rules are evaluated with **stop and level termination taking precedence over timed progression**. Unlisted conditions retain the current step.

| Current step | Receptivity | Next step |
|---|---|---|
| Any step | `stop` | Step 0 |
| Any step | `NOT stop AND (LSH OR LSHH)` | Step 0 |
| Step 0 | `start AND NOT stop AND NOT LSH AND NOT LSHH` | Filling step |
| Filling step | `ton_q AND NOT stop AND NOT LSH AND NOT LSHH` | Pause step |
| Pause step | `NOT tof_q AND NOT stop AND NOT LSH AND NOT LSHH` | Filling step |

A `start` event outside Step 0 has no effect. A held start button does not automatically restart the sequence after stopping or reaching the level limit.

### Timer controls

- **TON:** IN is exactly the **filling-step activity**; PT is `TON_Duration`.
  - `ton_q` becomes TRUE after uninterrupted filling-step activity for `TON_Duration`.
  - Leaving the filling step makes IN FALSE and resets TON.
- **TOF:** IN is exactly the **filling-step activity**; PT is `TOF_Duration`.
  - `tof_q` is TRUE during filling.
  - Leaving filling starts the off-delay; `tof_q` remains TRUE for `TOF_Duration`.
  - The pause step ends when `tof_q` becomes FALSE.
- Entering Step 0 does **not** require forcing TOF Q immediately FALSE. Its remaining TRUE cannot open a valve or restart filling because Step 0 requires `start`.

### Output controls

- `fill_valve` is TRUE only in the filling step and only while `stop`, `LSH`, and `LSHH` are all FALSE.
- `discharge_valve` is always FALSE.
- Initialization and any asserted `stop` produce Step 0 and both outputs FALSE.

## Safety assumptions and limits

**Additional protective assumption:** The task requires that `LSHH` never be reached but does not specify its transition behavior. This model treats `LSHH` as a shutdown interlock: it closes the fill valve, returns to Step 0, and inhibits a new start while asserted. This is a backup response, not the normal filling endpoint.

Normal termination occurs at `LSH` at 2.4 m. Proving that the level never reaches 2.7 m additionally requires confirming that the 0.3 m margin accommodates input/communication latency, PLC scan time, valve closing time, and residual inflow. The discrete control model alone cannot establish that physical guarantee.

For initialization, this model assumes a start button already held at startup is **not** a new press; release and repress are required. Timer instances and the sequence state must begin in their defined inactive/Step 0 conditions.
