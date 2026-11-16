## A0 context model — Control timed tank filling

**Purpose:** Fill the tank in alternating filling and pause phases until `LSH` detects liquid, while honoring stop commands and keeping the discharge valve closed.

**Boundary:** The control model includes command conditioning, step sequencing, timer operation, and output-command generation. The tank, valves, switches, and communications interface are external plant/interface mechanisms.

In the tables below, **inputs** are information transformed by a function; **controls** govern its execution; **outputs** are information or commands produced; and **mechanisms** are the resources performing it. Every function name is a verb phrase, and every arrow label is a noun phrase or the required signal identifier.

### Context ICOM

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| A0 | Control timed tank filling | `StartCommand`; `StopCommand`; `LSH`; `LSHH` | `TON_Duration`; `TOF_Duration`; initialization rule; start-event rule; filling-and-pause rules; stop-priority rule; level-completion rule; high-high protection rule; discharge-inhibition rule | `fill_valve`; `discharge_valve` | OpenPLC Runtime; cyclic execution; TON and TOF timer facilities; Modbus TCP interface; Factory I/O digital tank configuration |

## A0 decomposition

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| A1 | Condition operator commands and level signals | `StartCommand`; `StopCommand`; `LSH`; `LSHH` | Start-event rule; input-mapping specification; initialization rule | `start`; `stop`; `LSH`; `LSHH` | PLC input image; rising-edge detection memory; Modbus TCP interface |
| A2 | Select the active operating step | `start` | `stop`; `LSH`; `LSHH`; `ton_q`; `tof_q`; initialization rule; transition-priority rules; filling-and-pause rules | Operating-step status; filling-step activity | PLC cyclic execution; step-state memory |
| A3 | Generate filling and pause timing signals | Filling-step activity | `TON_Duration`; `TOF_Duration`; TON behavior specification; TOF behavior specification; timer-initialization rule | `ton_q`; `tof_q` | TON timer instance; TOF timer instance; PLC time base |
| A4 | Generate safe valve commands | Operating-step status | `stop`; `LSH`; `LSHH`; output-mapping specification; discharge-inhibition rule; valve-permission rule | `fill_valve`; `discharge_valve` | PLC output image; Modbus TCP interface; Factory I/O valve interface |

### Internal arrow connections

| Arrow | Source | Destination |
|---|---|---|
| `start` | A1 | A2 input |
| `stop` | A1 | A2 and A4 controls |
| `LSH` | A1 | A2 and A4 controls |
| `LSHH` | A1 | A2 and A4 controls |
| Operating-step status | A2 | A4 input |
| Filling-step activity | A2 | A3 input |
| `ton_q` | A3 | A2 control |
| `tof_q` | A3 | A2 control |

The A2–A3 feedback represents cyclic sequencing and timing, not an instantaneous combinational loop. Timer and step-state updates must have a defined scan-order convention during implementation.

## Behavioral controls attached to the model

### Operating steps and transitions

The following table defines the **transition-priority rules** and **filling-and-pause rules**. Conditions use the required receptivity identifiers.

| Priority | Current step | Receptivity | Next step |
|---|---|---|---|
| 1 | Any step | `stop` | Step 0 |
| 2 | Any step | `LSHH` | Step 0 |
| 3 | Any step | `LSH` | Step 0 |
| 4 | Step 0 | `start AND NOT stop AND NOT LSH AND NOT LSHH` | Filling step |
| 4 | Filling step | `ton_q AND NOT LSH` | Pause step |
| 4 | Pause step | `NOT tof_q` | Filling step |

Otherwise, the current step remains active. Higher-priority conditions override lower-priority transitions.

- **Initialization rule:** Step 0 is initially active; both valve commands are FALSE; timers and edge-detection memory are initialized deterministically.
- **Start-event rule:** `start` is TRUE for only the scan detecting a rising edge of `StartCommand`. `stop` follows the level of `StopCommand`.
- **Filling-step activity:** TRUE only while the filling step is active.
- **TON behavior specification:** TON receives filling-step activity as its IN and `TON_Duration` as its preset. Its Q is `ton_q`.
- **TOF behavior specification:** TOF receives the same filling-step activity as its IN and `TOF_Duration` as its preset. Its Q is `tof_q`. It remains TRUE during filling and for the specified delay after filling ends.
- **Valve-permission rule:** `fill_valve` is TRUE only in the filling step and only when `stop`, `LSH`, and `LSHH` are all FALSE.
- **Discharge-inhibition rule:** `discharge_valve` is always FALSE.
- Step 0 and the pause step command both valves FALSE.

### I/O mapping controls

| Scene/runtime tag | Address | Model identifier |
|---|---|---|
| `StartCommand` | `%IX100.0` | `start`, after rising-edge detection |
| `StopCommand` | `%IX100.1` | `stop` |
| `LSH` — 2.4 m | `%IX100.2` | `LSH` |
| `LSHH` — 2.7 m | `%IX100.3` | `LSHH` |
| `FillValve` | `%QX100.0` | `fill_valve` |
| `DischargeValve` | `%QX100.1` | `discharge_valve` |

### High-high safety qualification

The `LSHH` abort is an explicit protective design choice supporting the requirement that high-high level must never be reached. **Normal completion occurs at `LSH`, not `LSHH`.** An `LSHH` interlock alone cannot guarantee that 2.7 m is never reached: that also requires verification of switch placement, maximum inflow, communications/scan latency, and valve-closing delay against the available 0.3 m margin.
