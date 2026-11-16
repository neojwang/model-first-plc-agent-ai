## A0 context and decomposition

**A0 — Control timed tank filling**

The model boundary includes input-event detection, step management, timing, and output generation. The tank and its switches belong to the external plant.

```text
                          Controls
          TimerDuration, sequence rules, I/O mapping
                              |
                              v
Inputs                  +----------------------+       Outputs
StartCommand ---------->| A0                   |------> fill_valve
StopCommand ----------->| Control timed        |------> discharge_valve
LSHH ------------------>| tank filling         |
                        +----------------------+
                              ^
                              |
                          Mechanisms
             OpenPLC Runtime, PLC timer service,
             Modbus TCP connection, Factory I/O
```

The child functions are a **functional decomposition**, not sequential process steps. In particular, A1–A4 are function identifiers; **step 0** and the **filling step** are controller states.

### ICOM table

Every listed arrow is a noun phrase or a prescribed signal identifier.

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control timed tank filling** | StartCommand; StopCommand; LSHH | TimerDuration; initial-step rule; start-event rule; filling-termination rule; stop-priority rule; discharge-inhibition rule; I/O address mapping | fill_valve; discharge_valve | OpenPLC Runtime; PLC timer service; Modbus TCP connection; Factory I/O tank scene |
| **A1** | **Derive command events and switch conditions** | StartCommand; StopCommand; LSHH | start-event rule; I/O address mapping | start; stop; LSHH | OpenPLC input acquisition; rising-edge detector; previous-input memory; Modbus TCP connection |
| **A2** | **Manage the filling sequence** | start; stop; LSHH; timer_done | initial-step rule; start-event rule; filling-termination rule; stop-priority rule | step state | OpenPLC cyclic execution; step-state memory |
| **A3** | **Measure the filling duration** | step state | TimerDuration; timer-reset rule | timer_done | PLC timer service; PLC time base |
| **A4** | **Generate valve commands** | step state; stop; LSHH | filling-output rule; stop-priority rule; discharge-inhibition rule; I/O address mapping | fill_valve; discharge_valve | OpenPLC output update; Modbus TCP connection; Factory I/O valve interfaces |

**LSH treatment:** `LSH` at 2.4 m is available in the scene, but the stated requirements do not use it to start, stop, or otherwise modify filling. It therefore has **no functional arrow in this control model**. Its address remains part of the I/O configuration; it must not be substituted for `LSHH` as the termination condition.

## Child-function connections

| Arrow | Source | Destination | Meaning |
|---|---|---|---|
| StartCommand | A0 boundary | A1 | Raw start-button value |
| StopCommand | A0 boundary | A1 | Raw stop-button value |
| LSHH | A0 boundary, through A1 | A2, A4 | Overfill-limit condition |
| start | A1 | A2 | One-scan event on a FALSE-to-TRUE transition of StartCommand |
| stop | A1 | A2, A4 | Maintained StopCommand condition |
| step state | A2 | A3, A4 | Current controller state: step 0 or filling step |
| timer_done | A3 | A2 | Filling-timer elapsed condition |
| fill_valve | A4 | A0 boundary | Fill-valve command |
| discharge_valve | A4 | A0 boundary | Discharge-valve command |

The `step state` / `timer_done` connection forms a functional feedback loop: the filling state enables timing, and timer completion terminates that state.

## Controls and behavioral meaning

| Control arrow | Definition |
|---|---|
| **initial-step rule** | Initialize the controller in step 0. Step 0 commands both outputs FALSE. |
| **start-event rule** | Generate `start` only in the scan in which StartCommand changes from FALSE to TRUE. Accept `start` only in step 0; do not queue a start received during filling. |
| **filling-termination rule** | Leave the filling step when `timer_done` or `LSHH` is TRUE and return to step 0. A simultaneously asserted `LSHH` prevents a fill-valve opening. |
| **stop-priority rule** | Whenever `stop` is TRUE, select step 0 and command both outputs FALSE, regardless of other conditions. |
| **timer-reset rule** | Start a fresh timing interval on entry to the filling step. Reset the timer outside that step; elapsed time does not carry into a later filling cycle. |
| **filling-output rule** | Command `fill_valve` TRUE only while the effective state is the filling step and neither `stop` nor `LSHH` is TRUE. Apply termination decisions before issuing the output command. |
| **discharge-inhibition rule** | Command `discharge_valve` FALSE in every state. |
| **I/O address mapping** | Bind the model’s signals to the OpenPLC/Factory I/O addresses listed below. |

### Receptivity semantics

- **Step 0 → filling step:** `start` AND NOT `stop` AND NOT `LSHH`.
- **Filling step → step 0:** `stop` OR `LSHH` OR `timer_done`.
- **Any state with `stop` TRUE:** step 0, with `fill_valve` FALSE and `discharge_valve` FALSE.
- `LSH` has no transition role.
- A held StartCommand does not generate another `start` after a cycle ends.

## I/O binding

| Model signal or parameter | Plant/runtime binding | Interpretation |
|---|---|---|
| start | Rising edge of StartCommand, `%IX100.0` | One-scan start event |
| stop | StopCommand, `%IX100.1` | Maintained stop condition |
| LSH | `%IX100.2` | Liquid detected at 2.4 m; unused by this task’s control logic |
| LSHH | `%IX100.3` | Liquid detected at the 2.7 m overfill limit |
| timer_done | Internal filling-timer result | TRUE when the filling timer reaches TimerDuration |
| fill_valve | FillValve, `%QX100.0` | TRUE opens the fill valve |
| discharge_valve | DischargeValve, `%QX100.1` | Always FALSE |
| TimerDuration | TIME parameter | Filling-timer preset |
