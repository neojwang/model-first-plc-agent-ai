| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control timed tank filling** | `start`; `stop`; `LSHH` | `TimerDuration`; initial-step rule; stop-priority rule; timer-or-high-high termination rule; discharge-valve prohibition | `fill_valve`; `discharge_valve` | OpenPLC Runtime; PLC scan cycle; Factory I/O tank scene; Modbus TCP connection and mapped I/O |
| **A1** | **Determine the operating step** | `start`; `stop`; `LSHH`; `timer_done` | Initial step 0; transition from step 0 to filling on `start`; return to step 0 on `timer_done` or `LSHH`; overriding return to step 0 while `stop` is TRUE | Operating step | OpenPLC transition logic; operating-step memory; PLC scan cycle |
| **A2** | **Measure the filling interval** | Operating step | `TimerDuration`; timer activation on entry to the filling step; timer reset outside the filling step | `timer_done` | OpenPLC timer instance; runtime time base |
| **A3** | **Generate the valve commands** | Operating step | Fill-valve activation only in the filling step; all-output deactivation in step 0; permanent discharge-valve deactivation | `fill_valve`; `discharge_valve` | OpenPLC output logic; mapped output image; Factory I/O Modbus TCP driver |

**Interpretation and boundary notes**

- **Arrow classification:** Commands and detected conditions are inputs because the controller evaluates them to determine its state. Parameters and behavioral rules are controls because they constrain that evaluation. Runtime software, memory, timing facilities, and communications are mechanisms.
- **Internal connections:** A1 supplies **Operating step** to A2 and A3. A2 returns `timer_done` to A1. These are functional dependencies, not a prescribed sequential execution order.
- **Initial and stopped behavior:** Step 0 produces `fill_valve = FALSE` and `discharge_valve = FALSE`. `stop` takes precedence over starting or continuing filling.
- **Signal vocabulary:** `start` denotes the specified one-scan press event, not the sustained value of `StartCommand`. `stop` and `LSHH` correspond to the respective Boolean input states. `timer_done` is internal; it is not a physical input.
- **Unused level switch:** `LSH` is available at the plant interface but has **no functional role in this task**. The requirements do not terminate filling at 2.4 m; termination is by elapsed time or `LSHH`. Consequently, `LSH` is not assigned an artificial dependency in the table.
- **Output mapping:** `fill_valve` maps to `FillValve AT %QX100.0`; `discharge_valve` maps to `DischargeValve AT %QX100.1` and remains FALSE.

Here, **A0** denotes the requested context function; in standard IDEF0 diagram numbering, its single-box context diagram is **A-0**, and its decomposition diagram is **A0**.
