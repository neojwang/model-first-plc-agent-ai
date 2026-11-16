### IDEF0 functional model

The model boundary is the **tank-control application**: it receives commands and level indications and produces valve commands. A0 is the context function; A1–A3 are its child functions. Step activity and timer outputs are internal arrows between the child functions, not additional external I/O.

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control timed tank filling** | `start`; `stop`; `LSH`; `LSHH` | `TON_Duration`; `TOF_Duration`; initial-step rule; filling/pause transition rules; stop priority; LSH completion rule; LSHH avoidance requirement; discharge inhibition rule | `fill_valve`; `discharge_valve` | OpenPLC Runtime; control program; Modbus TCP connection; Factory I/O digital-tank I/O |
| **A1** | **Determine filling-cycle step** | `start`; `stop`; `LSH`; `LSHH`¹; `ton_q`; `tof_q` | Initial step: step 0. Highest priority: `stop` selects step 0. During an active cycle, `LSH` selects step 0. Otherwise: step 0 + `start` selects filling; filling + `ton_q` + NOT `LSH` selects pause; pause + NOT `tof_q` selects filling. LSHH avoidance requirement. | Step-0 activity; filling-step activity; pause-step activity | OpenPLC Runtime; sequence logic; step-state memory |
| **A2** | **Time filling and pause intervals** | Filling-step activity | TON semantics with `IN` equal to filling-step activity and `PT := TON_Duration`; TOF semantics with `IN` equal to filling-step activity and `PT := TOF_Duration`; timer initialization rules | `ton_q`; `tof_q` | OpenPLC Runtime; TON instance; TOF instance; runtime time base |
| **A3** | **Generate valve commands** | Step-0 activity; filling-step activity; pause-step activity; `stop` | `fill_valve` TRUE only during filling and while NOT `stop`; `fill_valve` FALSE in step 0 and pause; `discharge_valve` always FALSE; stop override | `fill_valve`; `discharge_valve` | OpenPLC Runtime; output-image mapping; Modbus TCP connection; Factory I/O valve interfaces |

**Interpretation and review notes**

- **Internal connections:** A1 supplies step activities to A2 and A3. A2 returns `ton_q` and `tof_q` to A1. The TOF input is **filling-step activity**, not pause-step activity.
- **Identifier mapping:** `start` is the one-scan press event derived from StartCommand; `stop` corresponds to StopCommand. `fill_valve` and `discharge_valve` map to `%QX100.0` and `%QX100.1`, respectively.
- **Completion takes precedence over cycling:** once `LSH` is detected during an active cycle, the controller returns to step 0 rather than resuming filling after a pause.
- **¹ LSHH is an underspecified safety input.** The task supplies `LSHH` and requires that its level never be reached, but specifies no transition or output action triggered by `LSHH`. It is therefore retained as a safety-observation input without inventing a high-high trip. The stated logic closes the fill valve at `LSH`; guaranteeing that the liquid never reaches LSHH additionally depends on plant dynamics, detection and communication delays, and valve closure time.
