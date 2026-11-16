The model below treats the **PLC control function** as the system boundary. A0 is the context function; A1–A3 are its child functions. Internal arrows connect the children, including the feedback arrow `timer_done` from A2 to A1.

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control timed tank filling** | `start`; `stop`; `LSHH` | `TimerDuration`; initial-step rule; filling-sequence rules; stop-priority rule; valve-output rules | `fill_valve`; `discharge_valve` | OpenPLC Runtime; PLC program and state memory; Modbus TCP connection to Factory I/O |
| **A1** | **Determine the filling step** | `start`; `stop`; `LSHH`; `timer_done` | Initial state: step 0; start-event acceptance in step 0; transition to filling on `start`; return to step 0 on `timer_done` or `LSHH`; overriding return to step 0 whenever `stop` is TRUE | Filling-step status | PLC transition logic; step-state memory |
| **A2** | **Measure the filling interval** | Filling-step status | `TimerDuration`; timer activation on entry to the filling step; timer reset in step 0 | `timer_done` | PLC timer function; runtime time base |
| **A3** | **Generate valve commands** | Filling-step status; `stop` | `fill_valve` TRUE only during the filling step; all outputs FALSE in step 0; all outputs FALSE whenever `stop` is TRUE; `discharge_valve` always FALSE | `fill_valve`; `discharge_valve` | PLC output logic; mapped output image; Modbus TCP output interface |

**Interpretation and boundary notes**

- `start` is the specified **one-scan press event**, not a continuously TRUE button level. It initiates filling only from step 0; it does not restart the timer during filling.
- `stop` has highest priority. `LSHH` or `timer_done` ends filling without waiting for the other condition. A simultaneously active termination condition must not permit an opening pulse.
- `LSH` is available in the I/O configuration but is **not used by the stated control requirements**. It therefore has no functional arrow in this model; the target-level switch does not terminate timer-based filling.
- “Filling-step status” is an internal noun-phrase arrow identifying step 0 or the filling step. It links A1 to both A2 and A3.
- The I/O mapping implements `start`, `stop`, and `LSHH` through the specified input addresses, and `fill_valve` and `discharge_valve` through `%QX100.0` and `%QX100.1`, respectively. The capitalization and PLC tag declarations do not change the required functional arrow identifiers.
