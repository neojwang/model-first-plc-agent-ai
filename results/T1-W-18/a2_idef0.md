The model below treats the task as a **controller function**: its inputs are the two detection signals, and its output is the conveyor command. The conveyor and box are the controlled plant, not additional controller inputs or outputs.

A reset-dominant **RS** block is selected so that detection at B stops the conveyor even if both sensors are TRUE. This resolves the otherwise unspecified simultaneous-detection case consistently with keeping the box at B.

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control conveyor transfer from A to B** | `sensor_a`; `sensor_b` | Start-on-A requirement; stop-and-hold-at-B requirement; IEC 61131-3 bistable requirement; reset-priority policy; I/O address mapping | `conveyor` | OpenPLC Runtime; IEC 61131-3 RS function block; Modbus TCP connection; Factory I/O scene |
| **A1** | **Determine set and reset requests** | `sensor_a`; `sensor_b` | Sensor detection semantics; set request correspondence to `sensor_a`; reset request correspondence to `sensor_b`; input mapping (`sensor_a`: `%IX100.0`, `sensor_b`: `%IX100.1`) | Set request; reset request | OpenPLC input image; PLC program logic |
| **A2** | **Latch the conveyor run state** | Set request; reset request | IEC 61131-3 RS state-retention semantics; reset-priority policy | Retained run state | IEC 61131-3 RS function-block instance; OpenPLC Runtime |
| **A3** | **Publish the conveyor command** | Retained run state | Output mapping (`conveyor`: `%QX100.0`); TRUE-to-run convention | `conveyor` | OpenPLC output image; Modbus TCP driver; Factory I/O conveyor interface |

**Internal flow:** A1’s **Set request** and **Reset request** feed A2; A2’s **Retained run state** feeds A3.

**Bistable behavior:** `sensor_b = TRUE` resets the run state; otherwise, `sensor_a = TRUE` sets it; when both are FALSE, the state is retained. Thus, the conveyor continues after the box leaves A and remains stopped after detection at B until a subsequent set condition. The task does not specify an initial or power-up state.
