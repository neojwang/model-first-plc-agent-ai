## A0 context function — Control timed tank filling

**Scope:** Control the digital tank’s fill valve using a timed filling step, with a high-high level cutoff and a stop override. Keep the discharge valve closed.

The model uses two operating steps:

- **Step 0 — Idle:** initial step; both outputs are FALSE.
- **Filling step:** the fill valve is open and the filling timer is active.

### IDEF0 ICOM model

Semicolon-separated entries denote separate arrows. `—` means no arrow of that category.

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control timed tank filling** | StartCommand signal; StopCommand signal; LSH signal; LSHH signal | TimerDuration; initial-step rule; start-event rule; timer-or-high-high termination rule; stop-priority rule; discharge-inhibition rule; I/O address mapping | fill_valve; discharge_valve | OpenPLC Runtime; Factory I/O digital tank scene; Modbus TCP connection; capacitive level switches; PLC state and timer resources |
| **A1** | **Acquire commands and level indications** | StartCommand signal; StopCommand signal; LSH signal; LSHH signal | start-event rule; I/O address mapping; input-sampling rule | start; stop; LSH; LSHH | PLC input image; Modbus TCP connection; previous-start-state memory |
| **A2** | **Manage filling steps** | start; stop; LSHH; timer_done | initial-step rule; start-acceptance rule; timer-or-high-high termination rule; stop-priority rule | filling-step status; idle-step status | PLC execution engine; step-state memory |
| **A3** | **Measure filling duration** | filling-step status | TimerDuration; timer-start rule; timer-reset rule | timer_done | PLC timer resource; PLC time base |
| **A4** | **Command tank valves** | filling-step status; stop; LSHH; timer_done | idle-output rule; stop-priority rule; timer-or-high-high termination rule; discharge-inhibition rule; I/O address mapping | fill_valve; discharge_valve | PLC output image; Modbus TCP connection; Factory I/O valve interfaces |

### Child-function connections

These are the internal arrows of the A0 decomposition:

| Source | Arrow | Destination |
|---|---|---|
| A1 | start | A2 |
| A1 | stop | A2, A4 |
| A1 | LSHH | A2, A4 |
| A2 | filling-step status | A3, A4 |
| A3 | timer_done | A2, A4 |

Additional arrow dispositions:

- **LSH** is acquired by A1 but has **no downstream control use** in this task. Reaching 2.4 m does not terminate filling.
- **idle-step status** identifies the idle state; it is internal state information, not a physical output.
- **fill_valve** and **discharge_valve** leave A4 and cross the A0 boundary as the commanded plant outputs.

### Control-arrow definitions

| Control arrow | Definition |
|---|---|
| initial-step rule | Initialize the sequence in step 0, with both valve commands FALSE. |
| start-event rule | `start` is TRUE for one scan on a FALSE-to-TRUE transition of StartCommand. A held button does not generate repeated starts. |
| input-sampling rule | Use the sampled command and level-switch values for each PLC scan. |
| start-acceptance rule | Accept `start` only in step 0, with `stop` FALSE and `LSHH` FALSE. A start received during filling does not restart the timer. |
| timer-start rule | Start measuring elapsed filling time on entry to the filling step. |
| timer-reset rule | Reset the timer when the filling step is inactive; a new filling cycle receives a fresh timing interval. |
| timer-or-high-high termination rule | End filling when `timer_done` or `LSHH` is TRUE, whichever occurs first. Return to step 0 and command the fill valve closed. An already-active `LSHH` prevents opening the fill valve. |
| stop-priority rule | Whenever `stop` is TRUE, force step 0 and both outputs FALSE, regardless of start, timer, or level conditions. |
| idle-output rule | Step 0 commands both outputs FALSE. |
| discharge-inhibition rule | Command `discharge_valve` FALSE in every state. |

The feedback arrow **timer_done** from A3 to A2 represents the timer’s effect on the sequence. The eventual PLC implementation must evaluate timing, termination conditions, and output commands so that the fill command is removed in the scan that recognizes timeout, high-high level, or stop.

### I/O address mapping

The required logical identifier vocabulary is preserved below. Physical tag names identify the mapped interfaces, not additional logical receptivity names.

| Logical arrow | Physical tag / parameter | Address | Meaning |
|---|---|---|---|
| start | StartCommand | `%IX100.0` | One-scan pressing event derived from the raw input |
| stop | StopCommand | `%IX100.1` | TRUE while the stop input is asserted |
| LSH | LSH | `%IX100.2` | Liquid detected at 2.4 m; unused for termination |
| LSHH | LSHH | `%IX100.3` | Liquid detected at 2.7 m; terminates or inhibits filling |
| timer_done | Internal filling timer | Internal | Filling duration has elapsed |
| fill_valve | FillValve | `%QX100.0` | TRUE opens the fill valve |
| discharge_valve | DischargeValve | `%QX100.1` | Always FALSE |
| TimerDuration | TimerDuration | Parameter, `TIME` | Required filling duration |

**Initialization detail to confirm before coding:** if StartCommand is already TRUE at PLC startup, decide whether that counts as a press. The conservative interpretation is to require a release followed by a new press.
