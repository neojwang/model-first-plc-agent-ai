**Model boundary:** the controller, not the physical liquid-handling process. Inputs are the signals processed by the controller; controls are the operating rules and parameter; outputs are valve-command signals. The plant, sensors, runtime, and communications provide the implementation mechanisms.

The context function is shown as **A0**, as requested; its decomposition comprises **A1–A3**. Internal arrow names are noun phrases, while the prescribed signal identifiers are retained exactly.

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control timed tank filling** | `start`; `stop`; `LSHH` | `TimerDuration`; initial-step rule; filling-start rule; timer-or-overfill termination rule; unconditional stop-priority rule; discharge-valve inhibition rule | `fill_valve`; `discharge_valve` | OpenPLC Runtime; PLC control program; Factory I/O digital tank scene and capacitive level switches; Modbus TCP connection and I/O mapping |
| **A1** | **Determine the active filling step** | `start`; `stop`; `LSHH`; `timer_done` from A2; filling-step status feedback | Initial state: step 0; entry into the filling step on `start`; return to step 0 on `timer_done` or `LSHH`; overriding return to step 0 whenever `stop` is TRUE | Filling-step status, supplied to A2 and A3 and retained as state feedback | OpenPLC step-state logic; rising-edge detection for StartCommand; mapped digital-input interface |
| **A2** | **Time the filling step** | Filling-step status from A1 | `TimerDuration`; timer starts upon entry into the filling step; timer resets outside the filling step | `timer_done`, supplied to A1 | OpenPLC timer instance; runtime time base |
| **A3** | **Generate valve commands** | Filling-step status from A1; `stop` | `fill_valve` TRUE only in the filling step; all outputs FALSE in step 0; overriding output inhibition while `stop` is TRUE; `discharge_valve` always FALSE | `fill_valve`; `discharge_valve` | OpenPLC output logic; mapped digital-output interface; Modbus TCP connection to Factory I/O |

**Interpretation notes**

- `start` is the one-scan press event derived from StartCommand, not its sustained TRUE level.
- `LSH` is available in the scene but **unused by the specified control behavior**. It therefore has no functional arrow in this model: reaching the target level does not terminate filling.
- `timer_done` is an **internal arrow**, produced by A2 and consumed by A1, rather than an external context input.
- The termination conditions are evaluated with priority over filling: `stop` forces step 0 and both outputs FALSE; `LSHH` or `timer_done` ends filling. An active `LSHH` must not permit an effective fill command even if `start` occurs in the same scan.
- The output mappings are `fill_valve` → FillValve at `%QX100.0` and `discharge_valve` → DischargeValve at `%QX100.1`.
