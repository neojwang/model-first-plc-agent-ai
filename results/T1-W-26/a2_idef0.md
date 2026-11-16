The model below treats the **controller** as the system boundary. Thus, `sensor_a` and `sensor_b` are incoming information, and `conveyor` is the outgoing command; the box and conveyor are part of the controlled plant.

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control box transfer from A to B** | `sensor_a`; `sensor_b` | Start-on-A requirement; stop-at-B requirement; IEC 61131-3 bistable requirement; I/O address mapping | `conveyor` | OpenPLC Runtime; Modbus TCP connection to Factory I/O; IEC 61131-3 bistable function block |
| **A1** | **Determine the start request** | `sensor_a` | Start-on-A rule: detection at A requests conveyor operation; input mapping `%IX100.0` | Start request | OpenPLC input acquisition and Boolean logic; Modbus TCP connection |
| **A2** | **Determine the stop request** | `sensor_b` | Stop-at-B rule: detection at B requests conveyor stoppage; input mapping `%IX100.1` | Stop request | OpenPLC input acquisition and Boolean logic; Modbus TCP connection |
| **A3** | **Latch and issue the conveyor command** | Start request; Stop request | Bistable state-retention rule; stop-priority rule; output mapping `%QX100.0` | `conveyor` | OpenPLC Runtime; IEC 61131-3 **RS** function block; Modbus TCP output interface |

**Decomposition and behavior**

- A1’s **Start request** and A2’s **Stop request** are internal arrows feeding A3.
- A3 sets `conveyor` when the Start request is true, resets it when the Stop request is true, and retains its previous value when neither request is true.
- **Modeling choice:** the task permits either SR or RS and does not explicitly define simultaneous detections. This model selects a reset-dominant **RS** block, so `sensor_b` takes priority and the conveyor remains stopped when both sensors are true.
- The bistable’s retained state is internal to A3, not an additional external input.
