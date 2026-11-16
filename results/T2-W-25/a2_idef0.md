### Functional model

The model covers **control of the filling operation**, rather than the physical movement of liquid. Signal arrows use the required identifiers. `TimerDuration` is a control parameter; `timer_done` is an internal arrow between child functions.

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0 — context** | **Control timed tank filling** | `start`; `stop`; `LSHH` | `TimerDuration`; initial-step requirement; filling-sequence rules; stop-priority rule; output constraints | `fill_valve`; `discharge_valve` | OpenPLC Runtime; PLC scan execution; timer facility; Modbus TCP connection; Factory I/O digital tank scene and I/O mapping |
| **A1** | **Determine the operating step** | `start`; `stop`; `LSHH`; `timer_done` from A2; operating-step status feedback | Initial step 0; transition from step 0 to the filling step on `start`; transition from the filling step to step 0 on `timer_done` or `LSHH`; overriding transition to step 0 whenever `stop` is TRUE | Operating-step status | OpenPLC Runtime; PLC scan execution; step-state memory |
| **A2** | **Measure the filling interval** | Operating-step status from A1 | `TimerDuration`; timer activation on entry to the filling step; timer reset outside the filling step | `timer_done` | OpenPLC timer facility; runtime time base |
| **A3** | **Generate valve commands** | Operating-step status from A1; `stop` | `fill_valve` TRUE only during the filling step and while `stop` is FALSE; both outputs FALSE in step 0; `discharge_valve` always FALSE | `fill_valve`; `discharge_valve` | OpenPLC output logic; Modbus TCP connection; Factory I/O output mapping |

### Interpretation and boundary notes

- **Initial condition:** A1 initializes to step 0, A2 is reset, and A3 commands both outputs FALSE.
- **Starting:** `start` is the specified one-scan press event, not the sustained level of StartCommand. It initiates filling only from step 0.
- **Ending filling:** The first occurrence of `timer_done` or `LSHH` returns the sequence to step 0 and closes the fill valve.
- **Stop priority:** `stop` overrides starting and continued filling. Its direct connection to A3 makes the all-outputs-FALSE requirement explicit.
- **Unused sensor:** `LSH` is available in the scene but is **not used by the stated control requirements**. It therefore has no functional arrow in this model; the 2.4 m target level does not terminate filling.
- **Internal arrows:** Operating-step status links A1 to A2 and A3 and feeds back to A1; `timer_done` links A2 to A1. Neither is an external output of A0.
- **IDEF0 classification:** The event and sensor values are modeled as input data processed into state and command decisions. The prescribed sequence, priorities, parameter, and output constraints are controls. The listed runtime, timer, and communications facilities are mechanisms.
