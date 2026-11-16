The model boundary is the **PLC control function**, rather than the physical transport process. Thus, `sensor_a` and `sensor_b` are input information, and `conveyor` is the output command. A0 is the context function; A1–A3 are its child functions.

**Priority interpretation:** If both sensors are TRUE, stopping takes precedence so that the box remains at B. Accordingly, the model uses a reset-dominant IEC 61131-3 **RS** block. This resolves a simultaneous-input case that the task does not explicitly specify.

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control box transfer from A to B** | `sensor_a` — box-detection state at A; `sensor_b` — box-detection state at B | Start-on-A requirement; stop-and-hold-at-B requirement; bistable-command requirement; reset-dominance interpretation; I/O address mapping | `conveyor` — conveyor run command | OpenPLC Runtime; IEC 61131-3 RS function block; Modbus TCP connection; Factory I/O scene and driver |
| **A1** | **Determine the start request** | `sensor_a` | Start-on-A requirement; TRUE-as-detection convention; input mapping `sensor_a` → `%IX100.0` | Start request | OpenPLC input process image and Boolean logic; Factory I/O Modbus TCP interface |
| **A2** | **Determine the stop request** | `sensor_b` | Stop-at-B requirement; TRUE-as-detection convention; input mapping `sensor_b` → `%IX100.1` | Stop request | OpenPLC input process image and Boolean logic; Factory I/O Modbus TCP interface |
| **A3** | **Latch the conveyor command** | Start request; Stop request | Bistable-command requirement; command-retention rule when neither request is present; reset dominance when both requests are present; TRUE-as-run convention; output mapping `conveyor` → `%QX100.0` | `conveyor` | OpenPLC Runtime; IEC 61131-3 reset-dominant RS function block and its retained state; output process image; Factory I/O Modbus TCP interface |

**Internal arrow connections:** A1’s **Start request** feeds A3’s set input; A2’s **Stop request** feeds A3’s reset input. A3 produces `conveyor`, which is also the A0 boundary output. The RS block’s memory maintains the run command after the box leaves A and maintains the stopped command after detection at B.
