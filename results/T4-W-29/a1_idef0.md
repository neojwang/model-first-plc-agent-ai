## A0 context model — Control the tank level

**Boundary:** the PLC control application. The tank, valves, level transmitter, and operator are outside this boundary. Factory I/O and the Modbus TCP connection provide the plant interface.

The model separates:
- **Inputs:** data transformed by a function.
- **Controls:** conditions and rules governing a function.
- **Outputs:** results produced by a function.
- **Mechanisms:** resources executing or supporting a function.

### Context ICOM table

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control the tank level** | Start-command signal `StartCommand` at `%IX100.0`; stop-command signal `StopCommand` at `%IX100.1`; level-register value `LevelMeter` at `%IW100` | I/O mapping and scaling specification; `FULL_SCALE = 1000`; measuring span `h_span`; level target `h_sp = h_target = 0.8 h_span`; overfill limit `h_max = 0.9 h_span`; tolerance `eps = 0.02 h_span`; hold time `t_h = 10 s`; PID gains `Kp`, `Ti`, `Td`; operating-step rules; stop priority; output limits; integration-suspension rule; discharge opening of 40% | Fill-valve register value `FillValve` at `%QW100`; discharge-valve register value `DischargeValve` at `%QW101`; logical output `fill_valve`; logical output `discharge_valve` | OpenPLC Runtime; cyclic PLC task; PLC state, timer, and PID memory; Modbus TCP connection; Factory I/O analog scene interface |

## A0 decomposition

The child functions are:

- **A1 — Interpret the command and level signals**
- **A2 — Evaluate the regulation completion conditions**
- **A3 — Select the operating step**
- **A4 — Calculate the bounded PID demand**
- **A5 — Apply the valve commands**

### Child-function ICOM table

Every semicolon-separated item represents an arrow or an explicitly grouped arrow bundle.

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A1** | **Interpret the command and level signals** | Start-command signal `StartCommand`; stop-command signal `StopCommand`; level-register value `LevelMeter` | I/O mapping and scaling specification; `FULL_SCALE`; `h_span`; `h_target`; `h_max`; start-event definition | Start event `start`; stop condition `stop`; measured level `h`; level region `r` | OpenPLC input image; Modbus TCP connection; cyclic PLC task; start-edge memory |
| **A2** | **Evaluate the regulation completion conditions** | Measured level `h` | Level target `h_sp`; tolerance `eps`; hold time `t_h`; regulation authorization | Level error `e`; settlement condition `settled` | PLC arithmetic; continuous-condition timer; cyclic task time base |
| **A3** | **Select the operating step** | Current-step state | `start`; `stop`; `settled`; `r`; initial-step rule; start-acceptance rule; completion rule; stop-priority rule | Updated-step state; regulation authorization | PLC sequence-state memory; cyclic PLC task |
| **A4** | **Calculate the bounded PID demand** | Level error `e` | Regulation authorization; PID gains `Kp`, `Ti`, `Td`; PID time base; output limits of 0–100%; integration-suspension rule | Bounded fill demand | PID calculation facility; PID state memory; cyclic PLC task |
| **A5** | **Apply the valve commands** | Bounded fill demand | Regulation authorization; discharge opening of 40%; `FULL_SCALE`; I/O mapping and scaling specification; zero-output rule | Fill-valve register value `FillValve`; discharge-valve register value `DischargeValve`; logical output `fill_valve`; logical output `discharge_valve` | OpenPLC output image; Modbus TCP connection; Factory I/O analog scene interface |

The **updated-step state** feeds back to A3 as the **current-step state** on the next scan. The **regulation authorization** feeds A2, A4, and A5 as a control arrow.

## Internal arrow definitions and connections

The required vocabulary is retained exactly for `start`, `stop`, `settled`, `r`, `fill_valve`, and `discharge_valve`.

| Arrow | Source → destination | Meaning |
|---|---|---|
| `start` | A1 → A3 control | Event of pressing `StartCommand`; TRUE only for the scan detecting the press. |
| `stop` | A1 → A3 control | Current Boolean state of `StopCommand`. |
| Measured level `h` | A1 → A2 input | Level obtained from `LevelMeter`: `h = (LevelMeter / FULL_SCALE) × h_span`, with appropriate numeric precision. |
| `r` | A1 → A3 control | `LOW` when `h < h_target`; `MID` when `h_target <= h < h_max`; `HIGH` when `h >= h_max`. |
| Level error `e` | A2 → A4 input | Difference `h_sp − h`. |
| `settled` | A2 → A3 control | TRUE after `|e| <= eps` has remained continuously TRUE for `t_h` during the current regulation cycle. |
| Current-step state | State feedback → A3 input | Step retained from the preceding scan; initialized to step 0. |
| Updated-step state | A3 → state feedback | Selected idle or regulation step. |
| Regulation authorization | A3 → A2, A4, A5 controls | Permission to time settlement, execute regulation, and energize the valve outputs. |
| Bounded fill demand | A4 → A5 input | PID demand limited to 0–100% valve opening. |
| `fill_valve` | A5 → A0 boundary | TRUE while PID control is authorized to drive the fill valve, even if the instantaneous PID demand is zero. |
| `discharge_valve` | A5 → A0 boundary | TRUE while the discharge valve is commanded to its fixed 40% opening. |

## Governing controls

### Operating-step rules

| Condition | Required result |
|---|---|
| Initialization | Step 0; regulation unauthorized; both physical outputs zero; `fill_valve = FALSE`; `discharge_valve = FALSE`. |
| `stop = TRUE`, in any step | Step 0 with both physical outputs zero. Stop overrides starting and continued regulation. |
| Step 0, `start = TRUE`, and `stop = FALSE` | Enter regulation, subject to the overfill guard. |
| Regulation active, `settled = FALSE`, and `r <> HIGH` | Continue regulation. |
| Regulation active and either `settled = TRUE` or `r = HIGH` | Close both valves and return to step 0. |
| Step 0 without an accepted `start` | Remain in step 0 with zero outputs. |

**Overfill guard:** `r = HIGH` prevents a nonzero valve command, including when a start event occurs while the level is already at or above `h_max`.

The settlement timer resets when regulation is inactive or when `|e| > eps`. Its accumulated time must not carry into a later regulation cycle.

### PID and output rules

- During regulation, the fill demand is the PID result for `e = h_sp − h`, clamped to **0–100%**.
- Integral accumulation is suspended while the PID output is clamped.
- During regulation:
  - `FillValve = bounded fill demand × FULL_SCALE`, with percentage conversion and integer representation applied.
  - `DischargeValve = 0.4 × FULL_SCALE = 400`.
  - `fill_valve = TRUE`.
  - `discharge_valve = TRUE`.
- Without regulation authorization:
  - `FillValve = 0`.
  - `DischargeValve = 0`.
  - `fill_valve = FALSE`.
  - `discharge_valve = FALSE`.

With the specified scaling, the target, overfill threshold, and tolerance correspond respectively to **800**, **900**, and **20** level-register counts.

## Modeling notes

- “Step 0 drives no output” is modeled as **explicit zero commands**, not retention of previous output-register values.
- `fill_valve` and `discharge_valve` are logical activity indicators; `FillValve` and `DischargeValve` are the physical analog command values.
- The IDEF0 arrows express functional dependencies, not execution order. The later PLC design must ensure that stop and completion decisions suppress both output commands in the same scan.
- PID numerical form, scan period, and PID-state initialization/reset policy remain implementation decisions to be specified before coding; they must preserve the controls above.
