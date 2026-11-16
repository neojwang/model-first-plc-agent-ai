## A0 context — Control timed tank filling

**Scope:** Control the digital filling tank using alternating filling and pause phases. Stop filling at LSH, inhibit filling at LSHH, and keep the discharge valve closed.

The requested context function is **A0**; its decomposition comprises **A1–A4**. In conventional IDEF0 diagram numbering, the context diagram is **A-0**, containing the A0 function.

### IDEF0 ICOM model

Arrow labels below are noun phrases or the required signal identifiers. Function names are verb phrases.

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control timed tank filling** | StartCommand signal; StopCommand signal; LSH signal; LSHH signal | TON_Duration; TOF_Duration; step-transition rules; stop-priority rule; level-protection rules; initial-step requirement; discharge-inhibition requirement; I/O address map | fill_valve; discharge_valve | OpenPLC Runtime; cyclic PLC task; Modbus TCP connection; Factory I/O digital tank; level switches; valve actuators |
| **A1** | **Acquire commands and level indications** | StartCommand signal; StopCommand signal; LSH signal; LSHH signal | I/O address map; rising-edge detection rule; input-initialization rule | start; stop; LSH; LSHH | OpenPLC input image; Modbus TCP connection; rising-edge detector; previous-command memory |
| **A2** | **Manage filling and pause steps** | start; stop; LSH; LSHH; ton_q; tof_q | Step-transition rules; stop-priority rule; level-protection rules; initial-step requirement | Filling-step activity; active-step status | Cyclic PLC task; step-state memory |
| **A3** | **Evaluate filling and pause delays** | Filling-step activity | TON_Duration; TOF_Duration; TON timing semantics; TOF timing semantics; timer-initialization rules | ton_q; tof_q | TON instance; TOF instance; PLC time base |
| **A4** | **Command tank valves** | Filling-step activity | stop; LSH; LSHH; discharge-inhibition requirement; I/O address map | fill_valve; discharge_valve | OpenPLC output image; Modbus TCP connection; fill-valve actuator; discharge-valve actuator |

**Active-step status** is an internal status arrow identifying step 0, the filling step, or the pause step. It is not an additional physical output.

### Child-function connections

- **A1 → A2:** `start`, `stop`, `LSH`, `LSHH`.
- **A1 → A4:** `stop`, `LSH`, `LSHH`, serving as valve-inhibition controls.
- **A2 → A3 and A4:** Filling-step activity.
- **A3 → A2:** `ton_q`, `tof_q`.
- **A4 → A0 boundary:** `fill_valve`, `discharge_valve`.

## Controls governing the decomposition

### Step-transition rules

The following are behavioral controls, not implementation code. Conditions use the required receptivity identifiers.

| Current step | Receptivity / condition | Next step |
|---|---|---|
| Any step | `stop` | Step 0 |
| Any step | `LSH` or `LSHH`, with `stop` FALSE | Step 0 |
| Step 0 | `start`, with `stop`, `LSH`, and `LSHH` FALSE | Filling step |
| Filling step | `ton_q`, with `stop`, `LSH`, and `LSHH` FALSE | Pause step |
| Pause step | NOT `tof_q`, with `stop`, `LSH`, and `LSHH` FALSE | Filling step |
| Any step | No applicable transition | Current step |

- **Step 0** is the initial step and commands no valve opening.
- `start` is a one-scan rising-edge event, not the maintained StartCommand level. A held button therefore does not restart filling after completion or stopping.
- `stop` has highest priority.
- Level completion or protection takes priority over timed continuation.

### Timer controls

- The TON input is **Filling-step activity**. Its preset is **TON_Duration**, and its output is `ton_q`.
- The TOF input is the same **Filling-step activity**. Its preset is **TOF_Duration**, and its output is `tof_q`.
- During filling, `tof_q` is TRUE. After filling is left, it remains TRUE for TOF_Duration.
- In the pause step, `tof_q` becoming FALSE permits filling to resume.
- Leaving filling removes the TON input and resets the TON according to normal TON semantics.
- Stop forces the step and valve commands off immediately; the TOF output may remain TRUE internally during its off-delay. It does not directly command a valve.

### Valve controls and address mapping

| Required identifier | Physical tag | Address | Meaning |
|---|---|---|---|
| `start` | StartCommand | `%IX100.0` | Rising-edge event derived from the input |
| `stop` | StopCommand | `%IX100.1` | Maintained stop indication |
| `LSH` | LSH | `%IX100.2` | Level indication at 2.4 m |
| `LSHH` | LSHH | `%IX100.3` | High-high level indication at 2.7 m |
| `fill_valve` | FillValve | `%QX100.0` | TRUE only during filling, with `stop`, `LSH`, and `LSHH` FALSE |
| `discharge_valve` | DischargeValve | `%QX100.1` | Always FALSE |

### Safety interpretation

**LSH is the normal termination level.** The LSHH shutdown/inhibit above is an explicit protective interpretation of “LSHH must never be reached”; it is not a normal operating transition.

Software logic alone cannot guarantee that the physical level never reaches 2.7 m. That requires validation that the margin above LSH accommodates scan time, communications delay, valve closure time, and residual inflow. An LSHH trip can stop further filling, but cannot undo an already reached high-high level.
