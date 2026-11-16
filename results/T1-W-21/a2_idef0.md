The model below treats the **PLC control system** as the functional boundary: sensor signals enter the system, and the conveyor command leaves it. Internal arrows connect the child functions.

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control conveyor movement from A to B** | `sensor_a`; `sensor_b` | Start-on-A rule; stop-and-hold-at-B rule; IEC 61131-3 bistable requirement; I/O address mapping | `conveyor` | OpenPLC Runtime; IEC 61131-3 SR or RS function block; Modbus TCP connection to Factory I/O |
| **A1** | **Acquire box detection states** | `sensor_a`; `sensor_b` | Input mapping: `sensor_a` ↔ SensorA at `%IX100.0`, `sensor_b` ↔ SensorB at `%IX100.1`; TRUE-means-box-detected convention | Box detection states | OpenPLC input-image handling; Modbus TCP connection; Factory I/O sensor interfaces |
| **A2** | **Latch the conveyor command** | Box detection states | Start-on-A rule; stop-and-hold-at-B rule; IEC 61131-3 SR or RS requirement; selected bistable priority | Latched conveyor command | OpenPLC Runtime; IEC 61131-3 SR or RS function-block instance |
| **A3** | **Issue the conveyor command** | Latched conveyor command | Output mapping: `conveyor` ↔ Conveyor at `%QX100.0`; TRUE-means-run convention | `conveyor` | OpenPLC output-image handling; Modbus TCP connection; Factory I/O conveyor interface |

**Functional interpretation**
- A1 supplies the current box detection states to A2.
- A2 sets the stored command when `sensor_a` is TRUE, resets it when `sensor_b` is TRUE, and retains it when neither is TRUE.
- A3 publishes the stored command as `conveyor`; FALSE stops the conveyor.

**Unspecified behavior:** The task permits either SR or RS and does not explicitly define simultaneous detection or initialization behavior. If stopping at B must take precedence when both sensors are TRUE, select a reset-dominant **RS** block.
