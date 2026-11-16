### IDEF0 functional model

The context function is **A0 — Control timed tank filling**. Its children are A1–A4 below. Signal observations are treated as **inputs**, operating requirements and timer settings as **controls**, and the execution infrastructure as **mechanisms**. The timer outputs `ton_q` and `tof_q` are internal arrows between child functions, not external inputs to A0.

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control timed tank filling** | `start`; `stop`; `LSH`; `LSHH` | Initial-step requirement; filling/pause sequence rules; stop priority; high-level completion rule; prohibition on reaching LSHH; `TON_Duration`; `TOF_Duration`; discharge-valve inhibition; I/O mapping | `fill_valve`; `discharge_valve` | OpenPLC Runtime; Factory I/O Modbus TCP connection; configured digital-tank scene |
| **A1** | **Manage operating steps** | `start`; `stop`; `LSH`; `ton_q`; `tof_q` | Initial state = step 0; step-transition rules; stop priority; high-level completion rule | Operating-step state; filling-step activity | OpenPLC Runtime; step-state logic |
| **A2** | **Time the filling phase** | Filling-step activity | `TON_Duration`; TON semantics, with IN equal to filling-step activity | `ton_q` | OpenPLC Runtime; TON function-block instance |
| **A3** | **Time the filling interruption** | Filling-step activity | `TOF_Duration`; TOF semantics, with IN equal to filling-step activity | `tof_q` | OpenPLC Runtime; TOF function-block instance |
| **A4** | **Generate valve commands** | Filling-step activity; `stop` | Fill-valve activation only during filling; all-output inhibition during stop; discharge-valve inhibition; output-address mapping | `fill_valve`; `discharge_valve` | OpenPLC Runtime; output image; Factory I/O Modbus TCP driver |

### Interpretation of the controls and internal arrows

- **A1 — Step-transition rules**
  - Initialize in **step 0**.
  - From step 0, `start` initiates the **filling step**.
  - While filling, `LSH` ends filling and returns the sequence to step 0.
  - While filling, `ton_q` together with NOT `LSH` selects the **pause step**.
  - While paused, NOT `tof_q` resumes filling, provided the sequence has not been stopped or completed by `LSH`.
  - `stop` has priority and returns the sequence to step 0.

- **A2/A3 — Timer connections:** A1’s **filling-step activity** feeds both timer inputs. A2 returns `ton_q` to A1; A3 returns `tof_q` to A1. Leaving filling starts the TOF off-delay; it does **not** immediately make `tof_q` FALSE.

- **A4 — Output rules:** `fill_valve` is TRUE only during filling and when `stop` is FALSE. `discharge_valve` is always FALSE. Thus step 0 and the pause step drive no valve output.

- **LSHH boundary:** `LSHH` is an available external observation, and “LSHH must never be reached” is a control constraint on A0. The task specifies **no transition or additional output driven by `LSHH`**, so it is not assigned an invented interlock in the child model. Nor does the task provide enough plant-dynamic information to prove that the 2.7 m limit cannot be reached.

Here, `start` denotes the specified one-scan press event, rather than the sustained state of `StartCommand`. The output arrows `fill_valve` and `discharge_valve` map respectively to `%QX100.0` and `%QX100.1`.
