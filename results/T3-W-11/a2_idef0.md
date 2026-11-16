### IDEF0 functional model

The context function **A0, “Control timed tank filling,”** is decomposed into three child functions. Signal arrows use the required identifier vocabulary; internal arrows describe the active step and its activity.

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control timed tank filling** | `start`; `stop`; `LSH`; `LSHH` | `TON_Duration`; `TOF_Duration`; initial-step requirement; filling/pause sequencing rules; stop priority; upper-level completion rule; safety constraint that `LSHH` must never be reached; requirement that `discharge_valve` remain FALSE | `fill_valve`; `discharge_valve` | OpenPLC Runtime; PLC control program; TON and TOF function-block instances; Modbus TCP connection; Factory I/O tank sensors and valve actuators |
| **A1** | **Determine the active operating step** | `start`; `stop`; `LSH`; `LSHH`; `ton_q`; `tof_q` | Initial active step: step 0; step-transition rules stated below; stop priority; upper-level completion rule; safety constraint that `LSHH` must never be reached | Active-step state; filling-step activity | PLC sequence logic; retained step-state variable; OpenPLC scan execution |
| **A2** | **Evaluate filling and pause timing** | Filling-step activity | `TON_Duration`; `TOF_Duration`; TON semantics; TOF semantics; both timer inputs equal to filling-step activity | `ton_q`; `tof_q` | TON function-block instance; TOF function-block instance; OpenPLC time base |
| **A3** | **Set the valve commands** | Active-step state | Filling-step output rule; step-0 and pause-step output rules; requirement that `discharge_valve` remain FALSE | `fill_valve`; `discharge_valve` | PLC output logic; output image; Modbus TCP output mapping; Factory I/O valve actuators |

### Controls defining the child functions

- **A1 — Step-transition rules**
  - Initialize in **step 0**.
  - Whenever `stop` is TRUE, select **step 0**, overriding filling and pause transitions.
  - From step 0, `start` initiates the **filling step**, provided the upper-level completion condition does not apply.
  - When `LSH` is TRUE, terminate the filling cycle and select **step 0**; do not resume filling from the pause step.
  - In the filling step, `ton_q AND NOT LSH` selects the **pause step**.
  - In the pause step, `NOT tof_q`, with neither stop nor upper-level completion applicable, selects the **filling step**.
  - Otherwise, retain the active step.

- **A2 — Timer controls**
  - TON uses filling-step activity as its input and `TON_Duration` as its preset. Its output is `ton_q`.
  - TOF uses the same filling-step activity as its input and `TOF_Duration` as its preset. Its output, `tof_q`, remains TRUE for the specified off-delay after filling-step activity becomes FALSE.
  - Leaving the filling step resets TON according to normal TON semantics.

- **A3 — Output controls**
  - Filling step: `fill_valve = TRUE`.
  - Step 0 or pause step: `fill_valve = FALSE`.
  - Every step: `discharge_valve = FALSE`.

**Signal interpretation:** `start` is the specified one-scan press event derived from StartCommand, not its continuously held level. The signals `start`, `stop`, `LSH`, and `LSHH` originate from the four specified input addresses; `fill_valve` and `discharge_valve` correspond to the two specified output addresses.

**Safety qualification:** The task specifies that `LSHH` must never be reached, but does not specify an additional transition triggered by `LSHH`. It is therefore represented as a monitored safety constraint, not an invented shutdown rule. Demonstrating that the constraint is satisfied also requires plant-response information, including residual inflow and sensing/actuation delays after `LSH` is detected.
