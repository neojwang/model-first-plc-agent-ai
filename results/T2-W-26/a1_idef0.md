## A0 context — Control timed tank filling

**Scope:** Control the fill valve using a start event, a filling timer, and high-high level protection. Keep the discharge valve closed.

The model uses the required identifiers for signal arrows. Other arrows represent internal state or configuration information.

### Signal definitions and boundary mapping

| Arrow identifier | Plant mapping or source | Meaning |
|---|---|---|
| `start` | Rising-edge event derived from `StartCommand` at `%IX100.0` | TRUE only during the scan in which the start button is pressed. |
| `stop` | `StopCommand` at `%IX100.1` | Stop request; TRUE has priority over filling. |
| `LSH` | `LSH` at `%IX100.2` | Liquid detected at 2.4 m. Available, but **not used by this task’s control logic**. |
| `LSHH` | `LSHH` at `%IX100.3` | Liquid detected at the 2.7 m overfill limit. |
| `timer_done` | Internal filling timer | Filling interval has elapsed. This is an internal arrow, not a physical input. |
| `fill_valve` | `FillValve` at `%QX100.0` | TRUE opens the fill valve. |
| `discharge_valve` | `DischargeValve` at `%QX100.1` | Always FALSE in this task. |

`LSH` is documented in the interface inventory but is deliberately not connected to a functional arrow: the requirements assign it no control role.

## ICOM model

In this model, commands and detected events are **inputs**; operating rules and parameter values are **controls**; the runtime, timer facility, and communications infrastructure are **mechanisms**.

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control timed tank filling** | `start`; `stop`; `LSHH` | `TimerDuration`; Initial-step rule; Start-event rule; Timer-or-high-high termination rule; Stop-priority rule; Discharge-closure rule | `fill_valve`; `discharge_valve` | OpenPLC Runtime; PLC scan cycle; Rising-edge detector; Timer facility; Modbus TCP connection; Factory I/O tank scene |
| **A1** | **Manage the filling cycle** | `start`; `stop`; `LSHH`; `timer_done` | Initial-step rule; Start-event rule; Timer-or-high-high termination rule; Stop-priority rule | Filling-step status | OpenPLC Runtime; PLC scan cycle; Rising-edge detector; Step-state memory |
| **A2** | **Measure the filling interval** | Filling-step status | `TimerDuration`; Timer enable-and-reset rule | `timer_done` | OpenPLC Runtime; Timer facility; PLC time base |
| **A3** | **Command the tank valves** | Filling-step status | Initial-step rule; Discharge-closure rule; Output-address mapping | `fill_valve`; `discharge_valve` | OpenPLC output image; Modbus TCP connection; Factory I/O valve interfaces |

### Control-arrow definitions

| Control arrow | Definition |
|---|---|
| Initial-step rule | Step 0 is the initial and idle step. Both valve commands are FALSE in this step. |
| Start-event rule | A `start` event accepted in step 0 initiates the filling step. A held start button does not generate repeated starts. |
| Timer-or-high-high termination rule | During filling, `timer_done` OR `LSHH` terminates filling and returns the sequence to step 0. An already-active `LSHH` must not permit a filling output. |
| Stop-priority rule | `stop = TRUE` forces step 0 and both outputs FALSE, regardless of a simultaneous `start` event. |
| Discharge-closure rule | `discharge_valve` remains FALSE in every step. |
| Timer enable-and-reset rule | The timer measures elapsed time while the filling step is active. It is reset in step 0 so each new filling cycle starts with a fresh interval. |
| Output-address mapping | `fill_valve` maps to `%QX100.0`; `discharge_valve` maps to `%QX100.1`. |

`Output-address mapping` and `Timer enable-and-reset rule` are supporting controls made explicit at the child level.

## Child-function interconnections

```text
start ─────────┐
stop ──────────┼──► A1 Manage the filling cycle
LSHH ──────────┤                │
timer_done ────┘                │ Filling-step status
      ▲                        ├─────────────────────────────┐
      │                        ▼                             ▼
      └────────── A2 Measure the filling interval   A3 Command the tank valves
                              ▲                             │
                              │                             ├──► fill_valve
                        TimerDuration                       └──► discharge_valve
```

- **A1 → A2:** **Filling-step status** enables or resets timing.
- **A2 → A1:** `timer_done` provides the elapsed-time termination event.
- **A1 → A3:** **Filling-step status** determines the valve commands.
- The feedback path is a functional dependency, not a prescribed program execution order. The eventual PLC implementation must ensure termination requests are reflected in the output image for the applicable scan.

## Step semantics

This table defines the sequencing rules that control A1; it is not PLC code.

| Current step | Condition | Resulting step | Required output state |
|---|---|---|---|
| Any | `stop = TRUE` | Step 0 | `fill_valve = FALSE`; `discharge_valve = FALSE` |
| Step 0 | No accepted `start` event | Step 0 | Both FALSE |
| Step 0 | `start = TRUE`, `stop = FALSE`, and `LSHH = FALSE` | Filling step | `fill_valve = TRUE`; `discharge_valve = FALSE`; timer starts |
| Step 0 | `start = TRUE` and `LSHH = TRUE` | Step 0 | Both FALSE |
| Filling step | `stop = FALSE`, `timer_done = FALSE`, and `LSHH = FALSE` | Filling step | `fill_valve = TRUE`; `discharge_valve = FALSE` |
| Filling step | `timer_done = TRUE` OR `LSHH = TRUE` | Step 0 | Both FALSE |

A `start` event received while filling is not queued. After any termination, a **new** `start` event is required for another filling cycle.
