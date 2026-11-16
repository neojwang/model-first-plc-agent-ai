The model below treats the **tank controller** as the system boundary, rather than the physical tank. **A0** is the requested context function; **A1–A3** are its child functions. Signal identifiers use the prescribed vocabulary; other arrows have noun-phrase names.

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control timed tank filling** | `start`; `stop`; `LSH`; `LSHH` | `TON_Duration`; `TOF_Duration`; initial-step requirement; filling-and-pause sequence rules; stop priority; level-completion rule; prohibition on reaching the high-high level; discharge-valve prohibition | `fill_valve`; `discharge_valve` | OpenPLC Runtime; controller program; TON and TOF function blocks; Modbus TCP interface; Factory I/O scene |
| **A1** | **Manage the operating sequence** | `start`; `stop`; `LSH`; `LSHH`; `ton_q`; `tof_q` | Initial state: step 0; `stop` priority over all other transitions; step 0 → filling on `start`; filling → pause on `ton_q` AND NOT `LSH`; pause → filling on NOT `tof_q`, provided filling has not ended; filling or pause → step 0 on `LSH`; high-high-level prohibition | Operating-step state; filling-step activity | OpenPLC cyclic execution; sequence-state memory; transition logic |
| **A2** | **Time filling and pause intervals** | Filling-step activity | `TON_Duration`; `TOF_Duration`; TON behavior with IN equal to filling-step activity; TOF behavior with IN equal to filling-step activity | `ton_q`; `tof_q` | TON function-block instance; TOF function-block instance; OpenPLC time base |
| **A3** | **Generate valve commands** | Operating-step state; `stop` | `fill_valve` TRUE only in the filling step; `fill_valve` FALSE in step 0 and pause; all outputs FALSE whenever `stop` is TRUE; `discharge_valve` permanently FALSE | `fill_valve`; `discharge_valve` | Output-assignment logic; OpenPLC output image; Modbus TCP output mapping |

**Internal arrow connections**

- **A1 → A2:** Filling-step activity.
- **A2 → A1:** `ton_q`, `tof_q`.
- **A1 → A3:** Operating-step state.

**Interpretation and limits**

- `start` is the specified one-scan press event, not the sustained value of StartCommand. `stop` is the current Boolean value of StopCommand.
- `LSH` represents the 2.4 m level switch; `LSHH` represents the 2.7 m switch. `fill_valve` maps to `%QX100.0`, and `discharge_valve` maps to `%QX100.1`.
- `LSH` completion and `stop` take precedence over timer-driven continuation. Thus, a pause must not resume filling after level completion.
- The task requires that `LSHH` never be reached, but supplies neither a specific `LSHH` transition nor physical stopping-margin data. The model therefore retains it as a safety observation and the high-high prohibition as a control; it does **not** silently invent an `LSHH` trip rule or claim that physical non-overshoot has been proved.
