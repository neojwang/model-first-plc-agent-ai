The model boundary is the **controller**: sensor indications enter as inputs, and the conveyor command leaves as an output. The conveyor and box are part of the controlled plant.

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control box transfer from A to B** | `sensor_a`; `sensor_b` | Start-on-A requirement; stop-at-B requirement; IEC 61131-3 bistable requirement; I/O address mapping | `conveyor` | OpenPLC Runtime; IEC 61131-3 RS function block; Modbus TCP connection to Factory I/O |
| **A1** | **Determine the start request** | `sensor_a` | Start-on-A rule; input mapping: `sensor_a` at `%IX100.0` | Start request | OpenPLC input processing; Modbus TCP input interface |
| **A2** | **Determine the stop request** | `sensor_b` | Stop-at-B rule; input mapping: `sensor_b` at `%IX100.1` | Stop request | OpenPLC input processing; Modbus TCP input interface |
| **A3** | **Maintain and issue the conveyor command** | Start request; Stop request | Bistable retention rule; reset-priority rule; output mapping: `conveyor` at `%QX100.0` | `conveyor` | IEC 61131-3 RS function block, including retained latch state; OpenPLC output processing; Modbus TCP output interface |

**Internal connections and behavior:**
- A1 supplies **Start request** to A3; A2 supplies **Stop request** to A3.
- A3 sets `conveyor` when the start request is true, resets it when the stop request is true, and otherwise retains its state.
- A reset-dominant **RS** block is selected so that detection at B stops the conveyor even if both sensors are true.
- A1 and A2 are parallel functions; their node numbers do not imply execution order.
