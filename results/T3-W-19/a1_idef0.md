# IDEF0 model — T3 Filling Tank with TON and TOF

## 1. Scope and modeling conventions

**A0 purpose:** Control intermittent tank filling until LSH detects liquid, using TON to limit each filling interval and TOF to determine each pause interval.

- **Inputs** are information transformed by a function.
- **Controls** are rules, parameters, and constraints governing that transformation.
- **Outputs** are information or commands produced by a function.
- **Mechanisms** are the resources executing the function.
- All function names below are verb phrases; arrow names are noun phrases or the required signal identifiers.

The raw device signals retain their supplied names at the system boundary. Within the control model, receptivities use exactly **start**, **stop**, **LSH**, **LSHH**, **ton_q**, and **tof_q**. Output commands use exactly **fill_valve** and **discharge_valve**.

**Safety interpretation:** LSH is the normal filling endpoint. This model additionally treats LSHH as a protective filling inhibit that returns the sequence to step 0. This is a conservative interpretation of “LSHH must never be reached,” not a substitute for preventing that level physically. Guaranteeing prevention requires adequate margin between LSH and LSHH for scan, communication, valve-closing, and residual-flow delays.

## 2. A0 context function

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| A0 | **Control timed tank filling** | StartCommand signal; StopCommand signal; LSH; LSHH | TON_Duration; TOF_Duration; initial-step rule; rising-edge start rule; filling/pause sequence rules; stop priority; LSH endpoint rule; LSHH protective-inhibit rule; discharge prohibition; I/O address mapping | fill_valve; discharge_valve | OpenPLC Runtime; PLC scan execution; TON and TOF function-block instances; Modbus TCP connection; Factory I/O tank scene, level switches, and valves |

**Context boundary:** The process supplies commands and level indications to A0. A0 produces valve commands. Physical tank dynamics remain outside the controller boundary.

## 3. A0 decomposition

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| A1 | **Acquire commands and level indications** | StartCommand signal; StopCommand signal; LSH input signal; LSHH input signal | Input address mapping; rising-edge start rule; startup edge-memory policy | start; stop; LSH; LSHH | OpenPLC input process image; Modbus TCP input exchange; rising-edge memory |
| A2 | **Determine the active sequence step** | start; stop; LSH; LSHH; ton_q; tof_q | Initial-step rule; transition rules; transition priority; LSH endpoint rule; LSHH protective-inhibit rule | Active-step indication; filling-step activity | OpenPLC sequence logic; retained interscan step memory |
| A3 | **Evaluate filling and pause timing** | Filling-step activity | TON_Duration; TOF_Duration; TON timing semantics; TOF timing semantics; timer initialization rules | ton_q; tof_q | OpenPLC TON instance; OpenPLC TOF instance; runtime time base |
| A4 | **Generate and transmit valve commands** | Active-step indication; stop; LSH; LSHH | Output authorization rules; discharge prohibition; output address mapping | fill_valve; discharge_valve | OpenPLC output logic and process image; Modbus TCP output exchange; Factory I/O valve interfaces |

### Internal arrow connections

| Arrow | Source | Destination |
|---|---|---|
| start; stop; LSH; LSHH | A1 | A2 |
| stop; LSH; LSHH | A1 | A4 |
| Filling-step activity | A2 | A3 |
| Active-step indication | A2 | A4 |
| ton_q; tof_q | A3 | A2 |
| fill_valve; discharge_valve | A4 | A0 boundary |

The A2–A3 feedback represents state-dependent timer evaluation across PLC scans, not an algebraic loop. Step memory and timer-instance memory preserve the necessary history.

## 4. Sequence rules governing A2

The sequence contains three mutually exclusive steps:

| Step | Function of the step | Output authorization |
|---|---|---|
| **0 — Idle** | Await a new start event | No output authorized |
| **1 — Filling** | Perform a timed filling interval | fill_valve authorized, subject to inhibits |
| **2 — Pause** | Wait for the off-delay interval to expire | No output authorized |

### Transition controls

Apply the following rules in priority order.

| Priority | Current step | Receptivity | Result |
|---|---|---|---|
| 1 | Any | stop | Return to step 0 |
| 2 | Any | LSHH | Return to step 0; inhibit filling |
| 3 | Any | LSH | Return to step 0; end filling |
| 4 | Step 0 | start AND NOT stop AND NOT LSH AND NOT LSHH | Enter step 1 |
| 5 | Step 1 | ton_q AND NOT LSH | Enter step 2 |
| 6 | Step 2 | NOT tof_q | Enter step 1 |

If no transition applies, retain the current step.

Additional controls:

- Initialize the sequence in **step 0**.
- **start** is TRUE only for the scan containing the rising edge of StartCommand.
- **stop** follows the level of StopCommand; it is not an edge event.
- A start event occurring during filling or pause does not queue another cycle.
- After a stop or normal completion, another filling cycle requires a new **start** event.
- Simultaneous **LSH** and **ton_q** ends filling rather than initiating a pause.
- Initialize start-edge memory so a StartCommand already held TRUE at controller startup does not produce an unintended start.

## 5. Timer controls governing A3

| Timer | Input information | Preset control | Output arrow | Required behavior |
|---|---|---|---|---|
| TON | Filling-step activity | TON_Duration | ton_q | Time continuously while step 1 is active. Assert ton_q after the preset interval. Reset elapsed timing and ton_q when step 1 becomes inactive. |
| TOF | Filling-step activity | TOF_Duration | tof_q | Assert tof_q while step 1 is active. After step 1 becomes inactive, retain tof_q for the preset interval, then clear it. |

Consequently:

- Leaving step 1 for step 2 starts the TOF off-delay.
- Step 2 ends when **tof_q** becomes FALSE.
- Each re-entry into step 1 begins a fresh TON filling interval.
- TOF may remain TRUE temporarily after a stop or LSH completion, but its value has **no authority to restart from step 0**.
- Timer and transition evaluation must preserve these semantics; entering pause must not cause an immediate restart because of a stale, pre-filling **tof_q** value.

## 6. Output controls governing A4

| Output arrow | Authorization rule |
|---|---|
| fill_valve | TRUE only when step 1 is active and stop, LSH, and LSHH are all FALSE |
| discharge_valve | Always FALSE |

Thus step 0 and step 2 drive neither valve. The direct inhibits also close the fill valve without waiting for a subsequent sequence-state update.

## 7. Boundary I/O mapping

| Boundary signal or command | Address | Internal interpretation |
|---|---|---|
| StartCommand | `%IX100.0` | Rising-edge source for start |
| StopCommand | `%IX100.1` | Source for stop |
| LSH | `%IX100.2` | Normal endpoint indication at 2.4 m |
| LSHH | `%IX100.3` | Protective high-high indication at 2.7 m |
| fill_valve → FillValve | `%QX100.0` | Fill-valve command |
| discharge_valve → DischargeValve | `%QX100.1` | Discharge-valve command, always FALSE |

The Factory I/O driver must map these scene tags to the specified OpenPLC addresses through its Modbus TCP slave connection.
