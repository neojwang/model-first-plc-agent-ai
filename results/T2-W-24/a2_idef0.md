### Scope and modeling conventions

The model covers the **OpenPLC control function**, not the physical filling process. Incoming command and sensor information is treated as input data; operating requirements and `TimerDuration` are controls. Internal arrows connect the child functions and do not become additional A0 boundary outputs.

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control timed tank filling** | `start`; `stop`; `LSHH` | `TimerDuration`; initial-step rule; timed-filling rule; high-high cutoff rule; stop-priority rule; discharge-inhibition rule | `fill_valve`; `discharge_valve` | OpenPLC Runtime; controller program; PLC timer facility; Modbus TCP connection; Factory I/O scene |
| **A1** | **Determine filling-step state** | `start`; `stop`; `LSHH`; `timer_done` | Initial-step rule; filling-step transition rules; stop-priority rule | Filling-step state | OpenPLC execution cycle; step-state memory |
| **A2** | **Measure filling-step duration** | Filling-step state | `TimerDuration`; timer activation and reset rules | `timer_done` | PLC timer facility; runtime time base |
| **A3** | **Generate valve commands** | Filling-step state | Valve-command rules; discharge-inhibition rule | `fill_valve`; `discharge_valve` | OpenPLC output logic; mapped Modbus output interface |

### Meaning of the controls and internal arrows

- **Filling-step state** is an internal noun-phrase arrow distinguishing **step 0** from the **filling step**. It connects A1 to A2 and A3.
- **Initial-step rule:** initialize in step 0.
- **Filling-step transition rules:**
  - `start` requests entry into the filling step.
  - `timer_done` or `LSHH` ends filling and returns the controller to step 0.
- **Stop-priority rule:** whenever `stop` is TRUE, step 0 takes precedence over any start or continued-filling request.
- **Timer activation and reset rules:** start timing on entry into the filling step; assert `timer_done` when `TimerDuration` has elapsed; reset the timer outside the filling step. The `timer_done` arrow connects A2 back to A1.
- **Valve-command rules:** `fill_valve` is TRUE only in the filling step and FALSE in step 0. A TRUE `LSHH` must prevent or terminate filling, including when it coincides with `start`.
- **Discharge-inhibition rule:** `discharge_valve` remains FALSE throughout the task.

### I/O interpretation

- `start` is the **one-scan press event** derived from `StartCommand`, not its continuously held level.
- `stop` represents `StopCommand`.
- `LSHH` is the high-high cutoff signal at 2.7 m.
- **`LSH` is available but unused in this task.** The requirements do not assign the 2.4 m switch any control function, so it is not shown as a consumed functional arrow.
- `fill_valve` and `discharge_valve` correspond to the specified physical output tags.
- `timer_done` is generated internally by A2; it is not an external input to A0.

The child functions are an **IDEF0 functional decomposition**, not sequential program steps. In particular, A1 and A2 exchange state and timer information during cyclic controller execution.
