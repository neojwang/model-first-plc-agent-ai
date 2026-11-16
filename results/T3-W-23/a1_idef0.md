## A0 context model

**A0 — Control timed tank filling**

The system fills the tank in timed phases separated by timed pauses. It returns to the initial step when the normal high-level switch operates or a stop is requested. The discharge valve remains closed.

In the tables below, semicolon-separated entries represent separate arrows. Signal identifiers are noun-phrase arrow labels; function names are verb phrases.

### ICOM decomposition

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control timed tank filling** | StartCommand samples; StopCommand samples; LSH samples; LSHH samples | TON_Duration; TOF_Duration; initial-step rule; filling-and-pause rules; stop-priority rule; normal-level termination rule; high-high-level prevention constraint; discharge-closure rule; I/O address map | fill_valve; discharge_valve | OpenPLC Runtime; PLC scan cycle; Modbus TCP connection; Factory I/O digital tank and level switches; TON timer instance; TOF timer instance |
| **A1** | **Acquire signals and detect the start event** | StartCommand samples; StopCommand samples; LSH samples; LSHH samples; previous StartCommand sample | I/O address map; rising-edge detection rule; startup edge-memory initialization rule | start; stop; LSH; LSHH; previous StartCommand sample | OpenPLC input image; Modbus TCP connection; edge-detection memory |
| **A2** | **Select the operating step** | start; stop; LSH; LSHH; ton_q; tof_q; operating-step state | Initial-step rule; transition rules; stop-priority rule; normal-level termination rule; defensive high-high shutdown rule; single-active-step rule | operating-step state | OpenPLC scan cycle; step-state memory |
| **A3** | **Measure the filling interval** | operating-step state | TON_Duration; TON behavior specification; filling-step activity rule | ton_q | TON timer instance; PLC time base |
| **A4** | **Measure the post-filling pause** | operating-step state | TOF_Duration; TOF behavior specification; filling-step activity rule | tof_q | TOF timer instance; PLC time base |
| **A5** | **Command the tank valves** | operating-step state; stop; LSH; LSHH | Output-assignment rules; stop-priority rule; normal-level cutoff rule; defensive high-high shutdown rule; discharge-closure rule; I/O address map | fill_valve; discharge_valve | OpenPLC output image; Modbus TCP connection; Factory I/O valve interfaces |

The state-memory arrows are feedback arrows, not additional external inputs to A0. Likewise, `start`, `stop`, `LSH`, `LSHH`, `ton_q`, and `tof_q` are internal arrows produced and consumed within the decomposition.

## Arrow connections and boundary mapping

### External I/O mapping

| Boundary arrow | Address | Internal identifier or destination |
|---|---|---|
| StartCommand samples | `%IX100.0` | A1 produces `start` |
| StopCommand samples | `%IX100.1` | A1 produces `stop` |
| LSH samples | `%IX100.2` | A1 produces `LSH` |
| LSHH samples | `%IX100.3` | A1 produces `LSHH` |
| fill_valve | `%QX100.0` | Physical tag `FillValve` |
| discharge_valve | `%QX100.1` | Physical tag `DischargeValve` |

`TON_Duration` and `TOF_Duration` are TIME-valued control arrows entering A0 and passing to A3 and A4, respectively.

### Internal arrow routing

| Arrow | Source | Destination |
|---|---|---|
| start | A1 | A2 |
| stop | A1 | A2; A5 |
| LSH | A1 | A2; A5 |
| LSHH | A1 | A2; A5 |
| previous StartCommand sample | A1 edge memory | A1, on the next scan |
| operating-step state | A2 | A2 state feedback; A3; A4; A5 |
| ton_q | A3 | A2 |
| tof_q | A4 | A2 |
| fill_valve | A5 | A0 output boundary |
| discharge_valve | A5 | A0 output boundary |

This balances the child model against A0: no child function introduces an undeclared external signal.

## Behavioral controls carried by the model

IDEF0 describes functional relationships rather than execution order. The following rules define the sequencing controls applied to A2–A5.

### Operating steps

| Step | Meaning | Valve behavior |
|---|---|---|
| **Step 0** | Initial/idle step | `fill_valve` FALSE; `discharge_valve` FALSE |
| **Filling step** | Active filling phase | `fill_valve` TRUE unless a stop or level cutoff applies; `discharge_valve` FALSE |
| **Pause step** | Timed interruption of filling | `fill_valve` FALSE; `discharge_valve` FALSE |

### Step-transition controls

Higher-priority rules override lower-priority rules. Evaluate transitions from the current step without cascading through multiple steps in one scan.

| Priority | Current step | Receptivity | Result |
|---|---|---|---|
| 1 | Any | `stop` | Return to step 0 |
| 2 | Any | `LSHH` | Return to step 0 — defensive shutdown |
| 3 | Any | `LSH` | Return to step 0 |
| 4 | Step 0 | `start AND NOT stop AND NOT LSH AND NOT LSHH` | Enter filling step |
| 4 | Filling step | `ton_q AND NOT LSH` | Enter pause step |
| 4 | Pause step | `NOT tof_q` | Enter filling step |
| — | Any | No applicable receptivity | Retain the current step |

Only the prescribed signal identifiers are used in the receptivities.

### Timer controls

- **A3 — TON:** Its IN condition is the activity of the filling step, and its preset is `TON_Duration`. Its Q output is `ton_q`. Leaving the filling step resets TON according to standard TON behavior.
- **A4 — TOF:** Its IN condition is also the activity of the filling step, and its preset is `TOF_Duration`. Its Q output is `tof_q`. It is TRUE during filling and remains TRUE for `TOF_Duration` after filling is left.
- The pause step ends only when `tof_q` becomes FALSE.
- Both timer instances are evaluated every scan, including idle and pause scans. Valve shutdown does not depend on waiting for TOF to expire.

### Start-event and output controls

- `start` is TRUE for one scan on a FALSE-to-TRUE transition of StartCommand. Holding the button does not generate repeated starts.
- Initialize the start-edge memory from the first acquired StartCommand sample, so a button already held at startup is not interpreted as a new press.
- `fill_valve` is TRUE only in the filling step while `stop`, `LSH`, and `LSHH` are all FALSE.
- `discharge_valve` is always FALSE.
- Following a stop or level termination, a new `start` event is required to begin another cycle.

## High-high-level constraint

**LSH at 2.4 m is the normal filling cutoff; LSHH at 2.7 m is not a normal transition target.** The LSHH shutdown above is a defensive addition, not a substitute for preventing that level.

The requirement that LSHH **never be reached** must also be validated against the plant: the 0.3 m margin must accommodate switch detection, Modbus updates, PLC scan time, valve closure time, and residual inflow. Closing the valve after `LSHH` becomes TRUE cannot, by itself, guarantee that LSHH was never reached.
