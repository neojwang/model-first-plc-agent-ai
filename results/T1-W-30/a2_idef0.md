The model below covers the **conveyor controller**, rather than the physical transport process. External signal arrows use the required identifiers exactly: `sensor_a`, `sensor_b`, and `conveyor`. Other arrows are internal information flows.

A reset-dominant **RS** bistable is selected so that detection at sensor B stops the conveyor even if both sensors are TRUE.

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control conveyor operation from A to B** | `sensor_a`; `sensor_b` | Start-on-A requirement; stop-and-hold-at-B requirement; IEC 61131-3 bistable requirement; reset-priority rule; I/O address mapping | `conveyor` | OpenPLC Runtime; IEC 61131-3 RS function block; Modbus TCP connection; Factory I/O driver |
| **A1** | **Determine start and stop requests** | `sensor_a`; `sensor_b` | Start request condition: `sensor_a = TRUE`; stop request condition: `sensor_b = TRUE` | Start request; stop request | OpenPLC Boolean logic |
| **A2** | **Latch the conveyor command** | Start request; stop request | IEC 61131-3 RS semantics: set on start request, reset on stop request, retain state when neither request is active; reset priority when both requests are active | Retained conveyor command | IEC 61131-3 RS function-block instance; OpenPLC Runtime state memory |
| **A3** | **Publish the conveyor command** | Retained conveyor command | Output mapping: `conveyor` → `%QX100.0`; TRUE = conveyor running, FALSE = conveyor stopped | `conveyor` | OpenPLC output image; Modbus TCP connection; Factory I/O driver |

**Arrow connections and boundary mapping**

- `sensor_a` enters **A0 → A1**, mapped from `SensorA AT %IX100.0`.
- `sensor_b` enters **A0 → A1**, mapped from `SensorB AT %IX100.1`.
- **A1 → A2:** Start request; stop request.
- **A2 → A3:** Retained conveyor command.
- `conveyor` leaves **A3 → A0 boundary**, mapped to `Conveyor AT %QX100.0`.

The bistable retains the run command after the box leaves sensor A and retains the stopped command after sensor B resets it. These are level-sensitive requests, not rising-edge events.
