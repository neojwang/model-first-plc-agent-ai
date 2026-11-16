The model below treats the **controller** as the functional boundary. Signal arrows use the prescribed identifiers; descriptive internal arrows are noun phrases. The mechanisms are the resources that execute the functions, rather than the signals being processed.

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control timed tank filling** | `start`; `stop`; `LSH`; `LSHH` | `TON_Duration`; `TOF_Duration`; initial-step requirement; filling/pause transition rules; stop priority; upper-level safety constraint; `discharge_valve` FALSE requirement | `fill_valve`; `discharge_valve` | OpenPLC Runtime; controller program; Modbus TCP connection; Factory I/O tank, switches, and valves |
| **A1** | **Manage filling-cycle steps** | `start`; `stop`; `LSH`; `ton_q`; `tof_q` | Initial step 0; stop priority; level-completion priority; filling/pause transition rules; upper-level limit status | Step state; filling-step activity | OpenPLC Runtime; step-sequencing logic |
| **A2** | **Time filling phases** | Filling-step activity | `TON_Duration`; TON semantics, with IN equal to filling-step activity | `ton_q` | OpenPLC Runtime; TON function-block instance |
| **A3** | **Time filling pauses** | Filling-step activity | `TOF_Duration`; TOF semantics, with IN equal to filling-step activity | `tof_q` | OpenPLC Runtime; TOF function-block instance |
| **A4** | **Determine valve commands** | Step state; filling-step activity; `stop` | Step 0 output prohibition; filling-only valve-opening rule; stop priority; `discharge_valve` FALSE requirement | `fill_valve`; `discharge_valve` | OpenPLC Runtime; Boolean output logic; Modbus TCP output mapping |
| **A5** | **Monitor the upper-level limit** | `LSHH` | Upper-level safety constraint: LSHH at 2.7 m must never be reached | Upper-level limit status | OpenPLC Runtime; LSHH input mapping |

### Interpretation of the functional controls

- **A1 — step sequencing**
  - Initialize in **step 0**.
  - With `stop` FALSE, `start` initiates the **filling step**, provided `LSH` is not already TRUE.
  - In the filling step, `LSH` TRUE ends filling and returns to step 0.
  - Otherwise, `ton_q` TRUE moves the sequence to the **pause step**.
  - In the pause step, `tof_q` FALSE resumes filling, provided `LSH` remains FALSE.
  - `LSH` TRUE ends the cycle from either active step.
  - `stop` TRUE overrides other conditions and returns the sequence to step 0.

- **A2–A3 — timer coupling:** both timers receive the same filling-step activity. Leaving filling resets TON and starts the TOF off-delay; TOF’s subsequent FALSE output permits filling to resume.

- **A4 — output rules:** `fill_valve` is TRUE only during filling and while `stop` is FALSE. `discharge_valve` is always FALSE.

### Boundary and safety qualifications

- `start` is the specified **one-scan press event**, derived from StartCommand—not the maintained button level. `stop` represents the level of StopCommand.
- Physical mappings are: `start` from `%IX100.0`, `stop` from `%IX100.1`, `LSH` from `%IX100.2`, `LSHH` from `%IX100.3`, `fill_valve` to `%QX100.0`, and `discharge_valve` to `%QX100.1`.
- **The task specifies that LSHH must never be reached, but does not specify an LSHH-triggered transition or shutdown action.** A5 therefore represents limit monitoring, not an invented interlock. Demonstrating that LSHH is unreachable also requires plant-response information—such as filling rate, scan/communication delay, and valve-closing delay—which is not supplied.
