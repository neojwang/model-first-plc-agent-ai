The model below treats the task as a **PLC control function**: it receives commands and level measurements and produces analog valve commands. **A0** is the context function; **A1–A5** are its child functions. Internal arrows appear as outputs of their producing functions and as inputs or controls of their consuming functions.

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control tank level** | StartCommand at `%IX100.0`; StopCommand at `%IX100.1`; LevelMeter at `%IW100` | I/O mapping and scaling; `FULL_SCALE = 1000`; measuring span `h_span`; `h_sp = h_target = 0.8 h_span`; `h_max = 0.9 h_span`; `eps = 0.02 h_span`; `t_h = 10 s`; PID gains `Kp`, `Ti`, `Td`; initial-step rule; start-event rule; stop-priority rule; completion rules; PID saturation and integration-suspension rules; discharge-opening rule | FillValve command at `%QW100`; DischargeValve command at `%QW101` | OpenPLC Runtime and PLC program; PLC scan clock; Modbus TCP connection; Factory I/O scene and driver |
| **A1** | **Interpret commands and level measurement** | StartCommand; StopCommand; LevelMeter | I/O mapping; `FULL_SCALE = 1000`; `h_span`; rising-edge definition of `start` | `start` — one-scan press event; `stop` — current stop condition; measured level `h` | PLC input-image access; rising-edge detector and previous-button-state memory; scaling arithmetic |
| **A2** | **Evaluate level conditions** | Measured level `h` | `h_sp`; `h_target`; `h_max`; `eps`; `t_h`; regulation-state status from A3; continuous in-band timing rule | Level error `e`; level region `r`; completion condition `settled` | PLC arithmetic and comparison operations; hold timer; PLC scan clock |
| **A3** | **Manage regulation sequence** | `start` | `stop`; `settled`; `r`; initial step 0; stop-priority rule; transition rules | Regulation-state status; `fill_valve`; `discharge_valve` | PLC sequence logic; retained sequence-state memory |
| **A4** | **Compute bounded PID demand** | Level error `e` | `fill_valve`; PID gains `Kp`, `Ti`, `Td`; PID execution interval; output limits of 0–100%; integration suspension while output is clamped | Bounded fill-opening demand | PID algorithm; PID state memory; saturation logic; integration-inhibition logic; PLC scan clock |
| **A5** | **Generate analog valve commands** | Bounded fill-opening demand | `fill_valve`; `discharge_valve`; `FULL_SCALE = 1000`; fixed discharge opening of 40%; zero-output rule for step 0 and stop; output-address mapping | FillValve command at `%QW100`; DischargeValve command at `%QW101` | PLC scaling and integer-conversion operations; PLC output-image access; Modbus TCP connection; Factory I/O driver |

### Arrow and behavior definitions

- **Measurement scaling:**  
  `h = (LevelMeter / FULL_SCALE) × h_span`. Equivalently, calculations may use normalized level or register units. In register-equivalent units, the target, overfill limit, and tolerance are respectively **800**, **900**, and **20**.

- **A2 conditions:**
  - `e = h_sp − h`.
  - `r = LOW` when `h < h_target`.
  - `r = MID` when `h_target ≤ h < h_max`.
  - `r = HIGH` when `h ≥ h_max`.
  - `settled` becomes TRUE after `|e| ≤ eps` has remained continuously true for 10 seconds during regulation. The hold timer is cleared when regulation is inactive or the error leaves the tolerance band.

- **A3 sequencing:**
  - Initialize in step 0 with `fill_valve = FALSE` and `discharge_valve = FALSE`.
  - A `start` event initiates regulation from step 0, provided `stop` is FALSE.
  - During regulation, both `fill_valve` and `discharge_valve` are TRUE.
  - `settled` or `r = HIGH` ends regulation and returns the sequence to step 0.
  - `stop` overrides all other conditions and returns the sequence to step 0 with both output enables FALSE.

- **A4–A5 output behavior:**
  - `fill_valve` is the **Boolean PID-drive enable**, not the analog valve-opening value.
  - While enabled, the PID demand is clamped to 0–100%, and integration is suspended while the output is clamped.
  - A5 converts that demand to a FillValve command in **0–1000**.
  - While `discharge_valve` is TRUE, DischargeValve is **400**.
  - In step 0, both analog commands are **0**; no prior nonzero command is retained.

The table is a functional decomposition, not an execution-order diagram. The scan implementation must nevertheless ensure that stop and termination decisions suppress both valve commands in the same scan.
