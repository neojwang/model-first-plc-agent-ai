## IDEF0 scope and conventions

**A0 — Control timed tank filling** is the context function. Its decomposition consists of **A1–A3** below. In standard IDEF0 diagram notation, the context diagram is **A-0**, containing the **A0** function box.

- **Inputs** are signals or information processed by a function.
- **Controls** are rules and parameters governing a function.
- **Outputs** are the results produced.
- **Mechanisms** are the resources performing the function.

Signal identifiers are retained exactly as specified. Other arrow names are noun phrases.

## ICOM model

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control timed tank filling** | `start`; `stop`; `LSHH` | `TimerDuration`; Initial-step rule; Stop-priority rule; Filling-completion rule; Discharge-inhibition rule | `fill_valve`; `discharge_valve` | OpenPLC Runtime; PLC cyclic execution; Start-edge detector; PLC timer; Modbus TCP interface; Factory I/O tank scene |
| **A1** | **Select the operating step** | `start`; `stop`; `LSHH`; `timer_done`; Current-step state | Initial-step rule; Stop-priority rule; Filling-entry rule; Filling-completion rule | Selected-step state | OpenPLC Runtime; Step-state memory |
| **A2** | **Measure the filling duration** | Selected-step state | `TimerDuration`; Timer-enable rule; Timer-reset rule | `timer_done` | OpenPLC Runtime; Non-retentive PLC timer; PLC time base |
| **A3** | **Command the tank valves** | Selected-step state; `stop`; `LSHH`; `timer_done` | Initial-step output rule; Filling-output rule; Stop-priority rule; Discharge-inhibition rule | `fill_valve`; `discharge_valve` | OpenPLC Runtime; Output image; Modbus TCP interface; Factory I/O valve actuators |

**State feedback:** **Selected-step state** is retained between scans and supplied to A1 as **Current-step state**. These are internal information arrows, not additional physical I/O.

## Controls and functional behavior

| Control arrow | Meaning |
|---|---|
| **Initial-step rule** | Initialize the sequence in step 0. |
| **Stop-priority rule** | Whenever `stop` is TRUE, select step 0 and force both outputs FALSE, regardless of other conditions. |
| **Filling-entry rule** | From step 0, accept `start` only when `stop` and `LSHH` are FALSE; select the filling step. |
| **Filling-completion rule** | In the filling step, select step 0 when `timer_done` or `LSHH` is TRUE. |
| **Timer-enable rule** | Enable timing while the selected step is the filling step. |
| **Timer-reset rule** | Reset elapsed time and `timer_done` whenever the selected step is step 0. |
| **Initial-step output rule** | In step 0, `fill_valve` and `discharge_valve` are FALSE. |
| **Filling-output rule** | Set `fill_valve` TRUE only in the filling step, with `stop`, `LSHH`, and `timer_done` all FALSE. |
| **Discharge-inhibition rule** | Keep `discharge_valve` FALSE in every step. |

The direct `stop`, `LSHH`, and `timer_done` inputs to A3 ensure that the valve command is removed in the scan in which a terminating condition is recognized, without waiting for a subsequent state-feedback scan.

## Arrow connections

- External **`start`**, **`stop`**, and **`LSHH`** → A1.
- A1 **Selected-step state** → A2 and A3.
- A1 **Selected-step state** → state memory → A1 **Current-step state**.
- A2 **`timer_done`** → A1 and A3.
- External **`stop`** and **`LSHH`** → A3.
- A3 **`fill_valve`** and **`discharge_valve`** → plant interface.

## Physical I/O correspondence

| Model identifier | Physical correspondence | Interpretation |
|---|---|---|
| `start` | Rising edge of `StartCommand` at `%IX100.0` | TRUE for one scan when the button is pressed; holding the button does not generate repeated starts. |
| `stop` | `StopCommand` at `%IX100.1` | Level-sensitive stop request. |
| `LSH` | `LSH` at `%IX100.2` | Liquid detection at 2.4 m; deliberately unused by this timer-based control. |
| `LSHH` | `LSHH` at `%IX100.3` | Liquid detection at the 2.7 m overfill limit. |
| `timer_done` | Internal timer completion indication | TRUE when the filling timer reaches `TimerDuration`. |
| `fill_valve` | `FillValve` at `%QX100.0` | TRUE opens the fill valve. |
| `discharge_valve` | `DischargeValve` at `%QX100.1` | Always FALSE. |

**Modeling decisions:** `LSH` is documented but has no functional arrow connection because the requirements assign it no control role. An already-active `LSHH` inhibits filling rather than permitting a momentary opening. After any stop or completion, a new `start` event is required for another filling cycle.
