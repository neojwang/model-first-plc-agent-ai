## A0 context and scope

**A0 — Control timed tank filling**

The modeled function controls the PLC sequence and valve commands. The simulated tank is part of the controlled environment, not part of the function being decomposed.

The sequence has two steps:

- **Step 0 — Idle:** both outputs are FALSE.
- **Step 1 — Filling:** `fill_valve` is TRUE while the filling timer runs, unless a termination condition is present.

`LSH` is available at the interface but has **no control effect** in this task. In particular, reaching 2.4 m does not end filling. Consequently, `LSH` is documented below but is not connected to a functional ICOM arrow.

### Interface vocabulary and mapping

| Model identifier | PLC interface | Meaning |
|---|---|---|
| `start` | Rising-edge event derived from `StartCommand` at `%IX100.0` | TRUE only during the scan in which the button is pressed |
| `stop` | `StopCommand` at `%IX100.1` | Stop request |
| `LSH` | `LSH` at `%IX100.2` | Target-level indication at 2.4 m; unused by this sequence |
| `LSHH` | `LSHH` at `%IX100.3` | High-high-level indication at 2.7 m |
| `timer_done` | Internal timer indication | Filling-step timer has elapsed |
| `fill_valve` | `FillValve` at `%QX100.0` | TRUE opens the fill valve |
| `discharge_valve` | `DischargeValve` at `%QX100.1` | Always FALSE |

The context boundary uses the normalized event `start`. Rising-edge detection of `StartCommand` is an interface responsibility; a continuously held button must not generate repeated `start` events.

## IDEF0 ICOM table

All function names are verb phrases. Arrow names are noun phrases or the required signal identifiers.

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control timed tank filling** | `start`; `stop`; `LSHH` | `TimerDuration`; Initialization policy; Transition policy; Timer policy; Valve command policy | `fill_valve`; `discharge_valve` | OpenPLC Runtime; PLC scan execution; Start-event detector; Modbus TCP connection; Factory I/O slave device |
| **A1** | **Manage filling sequence** | `start`; `stop`; `LSHH`; `timer_done`; Cycle step feedback | Initialization policy; Transition policy | Cycle step | PLC sequence-state storage; PLC scan execution |
| **A2** | **Measure filling interval** | Cycle step | `TimerDuration`; Timer policy | `timer_done` | PLC timer instance; Runtime timebase; PLC scan execution |
| **A3** | **Determine valve commands** | Cycle step; `stop`; `LSHH`; `timer_done` | Valve command policy | `fill_valve`; `discharge_valve` | PLC output image; Modbus TCP connection; Factory I/O valve interfaces |

**Arrow interpretation:** The input signals are treated as information transformed into sequence decisions and valve commands. The policies and `TimerDuration` constrain that transformation and therefore enter as controls.

## Control-arrow definitions

| Control arrow | Definition |
|---|---|
| **Initialization policy** | Initialize Cycle step to step 0. Initialize the timer to its reset state and both valve commands to FALSE. |
| **Transition policy** | Give `stop` highest priority. In step 0, accept `start` only when `stop` and `LSHH` are FALSE. In step 1, return to step 0 when `stop`, `LSHH`, or `timer_done` is TRUE. Ignore `start` while filling. |
| **Timer policy** | Start a fresh interval on entry to step 1. Assert `timer_done` when the active interval reaches `TimerDuration`. Reset the timer and clear `timer_done` outside step 1. |
| **Valve command policy** | Set `fill_valve` TRUE only in step 1 with `stop`, `LSHH`, and `timer_done` all FALSE. Set `discharge_valve` FALSE unconditionally. |

The `LSHH` start inhibition prevents opening the fill valve when the overfill indication is already TRUE.

## Child-function connections

The A0 decomposition contains these internal arrows:

| Source | Arrow | Destination |
|---|---|---|
| A1 | Cycle step | A2 input; A3 input |
| A1 | Cycle step feedback | A1 input, through retained state |
| A2 | `timer_done` | A1 input; A3 input |

**Cycle step feedback** is the retained value of **Cycle step**, not a separate state variable.

Boundary arrows are distributed as follows:

- `start` → A1.
- `stop` → A1 and A3.
- `LSHH` → A1 and A3.
- `TimerDuration` → A2.
- Initialization policy and Transition policy → A1.
- Timer policy → A2.
- Valve command policy → A3.
- A3 produces the A0 boundary outputs `fill_valve` and `discharge_valve`.

## Sequence behavior and precedence

| Current step | Condition, in priority order | Resulting step | Valve behavior |
|---|---|---|---|
| Any | `stop` | Step 0 | Both outputs FALSE |
| Step 0 | `start` AND NOT `LSHH`, with `stop` FALSE | Step 1 | Open `fill_valve`; begin timing |
| Step 0 | Otherwise | Step 0 | Both outputs FALSE |
| Step 1 | `LSHH` OR `timer_done`, with `stop` FALSE | Step 0 | Both outputs FALSE; reset timer on leaving filling |
| Step 1 | Otherwise | Step 1 | Keep `fill_valve` TRUE; continue timing |

The child functions are a **functional decomposition, not a prescribed execution order**. The implementation must ensure that `stop`, `LSHH`, or timer expiry suppresses `fill_valve` in the scan in which the condition is recognized. After termination, a new `start` event is required for another filling interval.
