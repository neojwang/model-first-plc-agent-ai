The context diagram **A-0** contains function **A0**; its decomposition contains **A1–A3**. This model treats the controller as the system boundary: sensor states are inputs, and the conveyor command is the output.

A reset-dominant **RS** block is selected from the permitted SR/RS alternatives so that detection at sensor B takes precedence if both sensors are TRUE.

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control box transfer from A to B** | `sensor_a`; `sensor_b` | Start-on-A rule; stop-at-B rule; IEC 61131-3 bistable-block requirement; reset-priority policy; I/O address mapping | `conveyor` | OpenPLC Runtime; IEC 61131-3 RS function block; Modbus TCP connection; Factory I/O scene and driver |
| **A1** | **Determine the start request** | `sensor_a` | Start-on-A rule: detection at A requests conveyor operation | Start request | OpenPLC Boolean logic |
| **A2** | **Determine the stop request** | `sensor_b` | Stop-at-B rule: detection at B requests conveyor stoppage | Stop request | OpenPLC Boolean logic |
| **A3** | **Latch the conveyor command** | Start request; Stop request | IEC 61131-3 bistable-block requirement; reset-priority policy; state-retention rule | `conveyor` | IEC 61131-3 RS function-block instance and its retained state; OpenPLC Runtime |

**Arrow definitions and connections**

- `sensor_a`: Boolean box-detection state at A, mapped to `%IX100.0`; connects **A0 → A1**.
- `sensor_b`: Boolean box-detection state at B, mapped to `%IX100.1`; connects **A0 → A2**.
- **Start request**: internal Boolean arrow from **A1 → A3**, equal to `sensor_a`.
- **Stop request**: internal Boolean arrow from **A2 → A3**, equal to `sensor_b`.
- `conveyor`: Boolean command from **A3 → A0**, mapped to `%QX100.0`; TRUE runs the conveyor.

The state-retention rule is: **set the command on a start request, reset it on a stop request, and otherwise retain its previous value**. Reset takes precedence when both requests are TRUE. Thus, the conveyor continues running after the box leaves A and stops when the box reaches B.
