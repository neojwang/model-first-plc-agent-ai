## 1. Model scope and conventions

The model describes the PLC control function, including input-event detection, step sequencing, timer evaluation, and output generation. It does not prescribe PLC code.

- **Inputs** are signals transformed or evaluated by a function.
- **Controls** are rules, parameters, and configuration governing the function.
- **Outputs** are produced signals or state information.
- **Mechanisms** are the resources performing the function.

All functions below have verb-phrase names. Arrow labels are noun phrases or the required signal identifiers.

### Signal vocabulary and mapping

The physical tag names below identify the interface. Receptivities and output commands use exactly the required identifiers.

| Physical tag or timer signal | Address or source | Model identifier | Meaning |
|---|---|---|---|
| StartCommand | `%IX100.0` | `start` | Rising-edge event, TRUE for one scan only |
| StopCommand | `%IX100.1` | `stop` | Current stop-button state |
| LSH | `%IX100.2` | `LSH` | Level-switch state at 2.4 m |
| LSHH | `%IX100.3` | `LSHH` | High-high level-switch state at 2.7 m |
| TON.Q | TON instance | `ton_q` | Filling-time limit indication |
| TOF.Q | TOF instance | `tof_q` | Filling-activity off-delay indication |
| FillValve | `%QX100.0` | `fill_valve` | Fill-valve command |
| DischargeValve | `%QX100.1` | `discharge_valve` | Discharge-valve command, always FALSE |

## 2. A0 context function

**A0 — Control timed tank filling**

The context boundary encompasses the OpenPLC control application. Factory I/O supplies plant signals and receives valve commands through the Modbus TCP interface.

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| A0 | Control timed tank filling | StartCommand signal; StopCommand signal; `LSH`; `LSHH` | Filling-cycle requirements; Initial-step requirement; Stop-priority rule; Level-limit rules; `TON_Duration`; `TOF_Duration`; I/O address mapping; PLC scan semantics | `fill_valve`; `discharge_valve` | OpenPLC Runtime; PLC task scheduler; Modbus TCP interface; Factory I/O scene interface |

## 3. A0 decomposition

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|---|
| A1 | Acquire inputs and detect the start event | StartCommand signal; StopCommand signal; `LSH`; `LSHH` | I/O address mapping; Rising-edge detection rule; Input-sampling rule | `start`; `stop`; `LSH`; `LSHH` | OpenPLC input image; Modbus TCP interface; Start-edge memory |
| A2 | Evaluate filling timers | Filling-step activity | `TON_Duration`; `TOF_Duration`; TON timing semantics; TOF timing semantics; Timer-execution rule | `ton_q`; `tof_q` | TON instance; TOF instance; PLC time base |
| A3 | Select the active filling step | `start`; `stop`; `LSH`; `LSHH`; `ton_q`; `tof_q` | Initial-step requirement; Step-transition rules; Transition-priority rule; Scan-order rule | Active-step state; Filling-step activity | PLC sequence logic; Step-state memory |
| A4 | Generate valve commands | Active-step state; `stop`; `LSH`; `LSHH` | Valve-command rules; Output-inhibition rule; Discharge-closure rule; I/O address mapping | `fill_valve`; `discharge_valve` | PLC output logic; OpenPLC output image; Modbus TCP interface |

### Internal arrow connections

These connections define the child model rather than leaving the ICOM lists as independent functions.

| Arrow | Source | Destination |
|---|---|---|
| `start` | A1 | A3 input |
| `stop` | A1 | A3 and A4 inputs |
| `LSH` | A1 | A3 and A4 inputs |
| `LSHH` | A1 | A3 and A4 inputs |
| Filling-step activity | A3 | A2 input |
| `ton_q` | A2 | A3 input |
| `tof_q` | A2 | A3 input |
| Active-step state | A3 | A4 input |
| `fill_valve` | A4 | A0 output boundary |
| `discharge_valve` | A4 | A0 output boundary |

The A0 input and control arrows are distributed to the children as shown in their ICOM entries. The PLC runtime and interface mechanisms support the relevant children.

## 4. Behavioral controls attached to the model

### Step-transition rules

The sequence has three mutually exclusive states: **Step 0**, **Filling step**, and **Pause step**.

Transitions are evaluated in the following priority order:

| Priority | Current state | Receptivity | Next state |
|---|---|---|---|
| 1 | Any state | `stop` | Step 0 |
| 2 | Any state | `LSHH` | Step 0 |
| 3 | Filling step or Pause step | `LSH` | Step 0 |
| 4 | Step 0 | `start AND NOT stop AND NOT LSH AND NOT LSHH` | Filling step |
| 5 | Filling step | `ton_q AND NOT LSH` | Pause step |
| 6 | Pause step | `NOT tof_q` | Filling step |

Otherwise, the current state is retained. **Step 0 is the initial state.** Start events during an active cycle are ignored, not queued.

### Timer controls

- Both timer instances execute every scan.
- TON uses filling-step activity as its IN and `TON_Duration` as its preset. Leaving the filling step resets TON.
- TOF uses the **same filling-step activity** as its IN and `TOF_Duration` as its preset.
- TOF.Q is TRUE during filling and remains TRUE for the off-delay interval after filling ends. The pause ends when `tof_q` becomes FALSE.
- A consistent scan-order rule must ensure that timers observe each filling-step activation and deactivation. Timer results are consumed at a defined transition-evaluation point; transitions are not repeatedly cascaded within one scan.

### Valve-command controls

| Active state or condition | `fill_valve` | `discharge_valve` |
|---|---:|---:|
| Step 0 | FALSE | FALSE |
| Filling step, without an inhibiting condition | TRUE | FALSE |
| Pause step | FALSE | FALSE |
| `stop OR LSH OR LSHH` | FALSE | FALSE |

The output-inhibition rule applies in the same scan that the relevant input is sampled, irrespective of timer state.

## 5. Safety interpretation

`LSH` is the normal filling termination condition. `LSHH` is modeled as an additional protective closure and return-to-Step-0 condition, not as a normal operating target.

**“LSHH must never be reached” is also a plant-level constraint.** Logical closure at `LSH` alone cannot guarantee it without adequate margin for scan delay, communications delay, valve-closing time, and residual inflow. Those effects must fit within the level margin between 2.4 m and 2.7 m. If they do not, the plant design or protective measures must change.
