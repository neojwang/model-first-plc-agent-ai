The model below treats the task as a **controller function**: sensor indications are transformed into the conveyor command. A reset-dominant **RS** block is selected so that detection at B stops the conveyor even if both sensors are TRUE.

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control box transfer from A to B** | `sensor_a`; `sensor_b` | Start-on-A rule; stop-and-hold-at-B rule; IEC 61131-3 bistable requirement; reset-priority rule; I/O address mapping | `conveyor` | OpenPLC Runtime; IEC 61131-3 RS function block; Modbus TCP connection; Factory I/O scene |
| **A1** | **Form the start request** | `sensor_a` | Start-on-A rule; input mapping: `sensor_a` ↔ SensorA at `%IX100.0` | Start request | OpenPLC input processing; Modbus TCP connection; Factory I/O sensor A |
| **A2** | **Form the stop request** | `sensor_b` | Stop-and-hold-at-B rule; input mapping: `sensor_b` ↔ SensorB at `%IX100.1` | Stop request | OpenPLC input processing; Modbus TCP connection; Factory I/O sensor B |
| **A3** | **Latch the conveyor command** | Start request; Stop request | IEC 61131-3 bistable requirement; reset priority; command-retention rule; output mapping: `conveyor` ↔ Conveyor at `%QX100.0` | `conveyor` | OpenPLC Runtime; RS function block with retained internal state between scans; Modbus TCP output connection to Factory I/O |

**Decomposition and behavior**

- **A1 → A3:** Start request follows `sensor_a` and drives the RS set input.
- **A2 → A3:** Stop request follows `sensor_b` and drives the RS reset input.
- **A3 → A0 boundary:** `conveyor` is the RS output: TRUE runs the conveyor; FALSE stops it.
- With neither request active, the RS block preserves its previous command. With both active, reset wins, keeping the conveyor stopped at B.

The priority choice resolves the otherwise unspecified simultaneous-sensor case; it is not an additional external input.
