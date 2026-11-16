## A0 — Control timed tank filling

**Purpose:** Fill the tank for no longer than `TimerDuration`, terminate filling early on `LSHH`, and force the idle condition whenever `stop` is TRUE.

The model uses **step 0 (idle)** and **step 1 (filling)**. Step 0 commands both outputs FALSE. `LSH` is monitored but does **not** terminate filling in this task.

### IDEF0 ICOM model

Each semicolon-separated item below is a noun-phrase arrow label. Function names are verb phrases.

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control timed tank filling** | Operator command signals; tank level signals | `TimerDuration`; initialization rule; stop-priority rule; filling-termination rule; discharge-inhibition rule; I/O mapping | Valve commands (`fill_valve`, `discharge_valve`) | OpenPLC Runtime; Factory I/O tank scene; Modbus TCP connection; level switches; valve actuators |
| **A1** | **Interpret commands and level signals** | Operator command signals; tank level signals | I/O mapping; start-edge definition | Start event (`start`); stop condition (`stop`); target-level condition (`LSH`); overfill condition (`LSHH`) | OpenPLC input image; start-edge memory; Modbus TCP connection |
| **A2** | **Select the active sequence step** | Start event (`start`); stop condition (`stop`); overfill condition (`LSHH`); timer-completion condition (`timer_done`) | Initialization rule; stop-priority rule; filling-termination rule | Active-step status | OpenPLC cyclic execution; sequence-state memory |
| **A3** | **Measure the filling interval** | Active-step status | `TimerDuration`; timer-enable rule; timer-reset rule | Timer-completion condition (`timer_done`) | OpenPLC timer service; timer-instance memory |
| **A4** | **Generate valve commands** | Active-step status; stop condition (`stop`); overfill condition (`LSHH`); timer-completion condition (`timer_done`) | Idle-output rule; discharge-inhibition rule; I/O mapping | Valve commands (`fill_valve`, `discharge_valve`) | OpenPLC output image; Modbus TCP connection; valve actuators |

### Child-function connections

- **A0 boundary → A1:** Operator command signals; tank level signals.
- **A1 → A2:** `start`, `stop`, `LSHH`.
- **A1 → A4:** `stop`, `LSHH`.
- **A2 → A3 and A4:** Active-step status.
- **A3 → A2 and A4:** `timer_done`.
- **A4 → A0 boundary:** `fill_valve`, `discharge_valve`.

`LSH` is an acquired, unused monitoring condition: it has no downstream control dependency in this task. It is shown as an **unconnected, tunneled child-level output**, not as an additional A0 output.

### Controls defining the behavior

| Control arrow | Definition |
|---|---|
| Initialization rule | The initial active step is step 0. |
| Start-edge definition | `start` is TRUE only for the scan containing a FALSE-to-TRUE transition of `StartCommand`. Holding the button does not generate additional start events. |
| Stop-priority rule | `stop` overrides all other conditions: select step 0 and command both outputs FALSE. |
| Filling-termination rule | In step 0, `start` requests step 1. During filling, `timer_done` or `LSHH` returns the sequence to step 0. Termination conditions override a simultaneous start request. |
| Timer-enable rule | The filling timer runs only while step 1 is active, using `TimerDuration`. |
| Timer-reset rule | The filling timer is reset outside step 1, so each accepted start begins a fresh filling interval. |
| Idle-output rule | `fill_valve` is TRUE only while step 1 is active and none of `stop`, `LSHH`, or `timer_done` is TRUE; otherwise it is FALSE. |
| Discharge-inhibition rule | `discharge_valve` is always FALSE. |

### I/O mapping control

| Model identifier | Plant tag or internal source | Address / meaning |
|---|---|---|
| `start` | Rising edge of `StartCommand` | `%IX100.0` |
| `stop` | `StopCommand` | `%IX100.1` |
| `LSH` | `LSH` | `%IX100.2`; liquid detected at 2.4 m |
| `LSHH` | `LSHH` | `%IX100.3`; liquid detected at 2.7 m |
| `timer_done` | Filling timer completion | Internal condition; no physical I/O address |
| `fill_valve` | `FillValve` | `%QX100.0`; TRUE opens the valve |
| `discharge_valve` | `DischargeValve` | `%QX100.1`; always FALSE |

Factory I/O operates as the Modbus TCP slave device attached to OpenPLC Runtime. No independent `LSH` cutoff, automatic restart, or additional operating mode is introduced.
