The model below treats **A0 as the controller’s context function**, with A1–A3 as its child functions. The physical box movement is performed by the plant; the controller produces `conveyor`.

A **reset-dominant RS bistable** is selected so that detection at B stops the conveyor even if both sensors are TRUE. This resolves the otherwise unspecified simultaneous-detection case consistently with the stopping requirement.

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control box transfer from A to B** | `sensor_a`; `sensor_b` | Start-on-A requirement; stop-and-hold-at-B requirement; IEC 61131-3 bistable requirement; reset-dominance policy; I/O address mapping | `conveyor` | OpenPLC Runtime; IEC 61131-3 RS function block; Modbus TCP connection; Factory I/O plant interface |
| **A1** | **Derive start and stop requests** | `sensor_a`; `sensor_b` | Start request equals detection at A; stop request equals detection at B; input mapping: `sensor_a` ← `%IX100.0` and `sensor_b` ← `%IX100.1` | Start request; stop request | OpenPLC input image and cyclic program execution; Modbus TCP input interface |
| **A2** | **Maintain the conveyor command** | Start request; stop request | IEC 61131-3 RS semantics: set on start request, reset on stop request, retain state when neither request is TRUE; reset dominance when both requests are TRUE | Retained conveyor command | Stateful RS function-block instance; OpenPLC Runtime |
| **A3** | **Apply the conveyor command** | Retained conveyor command | Output mapping: `conveyor` → `%QX100.0`; TRUE means conveyor running and FALSE means conveyor stopped | `conveyor` | OpenPLC output image; Modbus TCP output interface; Factory I/O conveyor actuator |

**Internal arrow connections:** A1’s **start request** and **stop request** feed A2; A2’s **retained conveyor command** feeds A3. The retained state is provided by the RS mechanism, not by an additional external input.
