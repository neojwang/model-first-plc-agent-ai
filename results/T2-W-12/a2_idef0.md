The model below treats the function as **controlling timed tank filling**, rather than physically filling the tank. Command and sensor signals are therefore information flows; the valve commands are outputs.

**Notation:** A0 is the overall function requested here; A1–A3 are its child functions. In standard IDEF0 notation, the context diagram displaying the overall function is numbered **A-0**, and its decomposition diagram is numbered **A0**.

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control timed tank filling** | **start** | **stop**; **LSHH**; **TimerDuration**; initial-step rule; stop-priority rule; timed-filling completion rule; discharge-valve closure requirement | **fill_valve**; **discharge_valve** | OpenPLC Runtime; PLC scan execution; timer facility; Modbus TCP connection; Factory I/O tank scene and mapped I/O |
| **A1** | **Manage filling-step transitions** | **start** | **stop**; **LSHH**; **timer_done**; initial-step rule; transition-priority rules | Filling-step status | OpenPLC Runtime; step-state memory; PLC scan execution |
| **A2** | **Measure filling-step duration** | Filling-step status | **TimerDuration**; timer enable-and-reset rules | **timer_done** | OpenPLC timer facility; runtime time base |
| **A3** | **Generate valve commands** | Filling-step status | **stop**; step-to-output rules; discharge-valve closure requirement | **fill_valve**; **discharge_valve** | OpenPLC output logic; mapped output image; Modbus TCP connection; Factory I/O valve interfaces |

### Meaning of the rules and internal arrows

- **Filling-step status** identifies either step 0 or the active filling step. It connects A1 to A2 and A3.
- **Initial-step rule:** initialize in step 0, with both valve commands FALSE.
- **Transition-priority rules:**
  - **stop** has highest priority and forces step 0.
  - In step 0, **start** initiates filling only when **stop** is FALSE and **LSHH** is FALSE.
  - During filling, **timer_done** or **LSHH** ends filling and returns the controller to step 0.
- **Timer enable-and-reset rules:** the timer runs while the filling step is active and resets when that step is inactive. **timer_done** is an internal arrow from A2 to A1, not a physical input.
- **Step-to-output rules:** **fill_valve** is TRUE only while the filling step is active and **stop** is FALSE. **discharge_valve** is always FALSE.
- **start** is the specified one-scan press event, not the maintained level of StartCommand. A held button therefore does not automatically restart filling.
- **LSH** has **no functional role in this task**. Although mapped at `%IX100.2`, it neither stops filling nor changes the timer or step state, so it is not an operative ICOM arrow.
- The operative mappings are **start** from StartCommand at `%IX100.0`, **stop** from `%IX100.1`, **LSHH** from `%IX100.3`, **fill_valve** to `%QX100.0`, and **discharge_valve** to `%QX100.1`.

Here, **stop**, **LSHH**, and **timer_done** are classified as *controls* because they govern whether the filling function may continue; they are not material or information being transformed into the valve commands.
