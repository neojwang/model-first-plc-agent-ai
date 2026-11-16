### IDEF0 functional model

The model boundary is the **controller**, not the physical tank. Consequently, its outputs are valve commands rather than liquid flow or tank level. As requested, **A0** denotes the context function, decomposed into **A1–A3**.

Signal identifiers retain the prescribed vocabulary. `start` is already the one-scan press event; `timer_done` is generated internally.

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control timed tank filling** | `start`; `stop`; `LSHH` | `TimerDuration`; initial-step rule; filling-start rule; timer-or-overfill termination rule; stop-priority rule; discharge-closure rule | `fill_valve`; `discharge_valve` | OpenPLC Runtime and control program; Modbus TCP connection; Factory I/O scene and mapped I/O |
| **A1** | **Manage the filling sequence** | `start`; `stop`; `LSHH`; `timer_done` | Step 0 as the initial state; filling entry on `start` from step 0; return to step 0 on `timer_done` or `LSHH`; overriding return to step 0 whenever `stop` is TRUE | Filling-step state | OpenPLC Runtime; sequence logic; retained sequence-state storage |
| **A2** | **Time the filling interval** | Filling-step state | `TimerDuration`; timer-start rule on filling entry; timer-reset rule outside filling | `timer_done` | OpenPLC Runtime; timer function block; PLC time base |
| **A3** | **Generate valve commands** | Filling-step state; `stop` | Fill-opening rule during filling only; all-outputs-FALSE rule in step 0 or while `stop` is TRUE; discharge-closure rule | `fill_valve`; `discharge_valve` | OpenPLC Runtime; output-assignment logic; mapped Modbus output channels |

### Interpretation and arrow connections

- **Internal connections:** A1 supplies **Filling-step state** to A2 and A3. A2 supplies `timer_done` to A1.
- **State behavior:** Step 0 is inactive. An accepted `start` enters filling and starts the timer. `timer_done` or `LSHH` ends filling, whichever occurs first. `stop` has overriding priority.
- **Output behavior:** `fill_valve` is TRUE only during filling and while `stop` is FALSE. `discharge_valve` is always FALSE.
- **Unused signal:** `LSH` is available from the plant but has no role in the stated requirements. It is therefore **not a functional arrow** in this model; reaching the 2.4 m target does not terminate filling.
- **No automatic restart:** Because `start` is a one-scan event, a held StartCommand does not initiate another cycle after the controller returns to step 0.
