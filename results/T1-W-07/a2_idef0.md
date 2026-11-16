### Functional model

The model covers the **conveyor controller**, rather than the physical transport process. Thus, `sensor_a` and `sensor_b` are information inputs, and `conveyor` is the Boolean command output. The physical conveyor and box are outside this functional boundary.

An IEC 61131-3 **RS** block is selected. Reset dominance ensures that the conveyor remains stopped when `sensor_b` is TRUE, including when both sensors are TRUE. The task does not explicitly specify simultaneous-sensor priority; this is a stated implementation choice.

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control conveyor transport from A to B** | `sensor_a`; `sensor_b` | Start-at-A requirement; stop-at-B requirement; bistable-command requirement; reset-priority convention; I/O address mapping | `conveyor` | OpenPLC Runtime; IEC 61131-3 RS function block; Modbus TCP interface to Factory I/O |
| **A1** | **Maintain the bistable conveyor command** | `sensor_a`; `sensor_b` | Start-at-A requirement; stop-at-B requirement; IEC 61131-3 RS semantics; reset-priority convention | Latched command | OpenPLC cyclic execution; RS function block with retained inter-scan state |
| **A2** | **Write the conveyor output** | Latched command | Output assignment rule; output address mapping | `conveyor` | OpenPLC output image; Modbus TCP interface; Factory I/O driver |

**Arrow definitions and connections**

- `sensor_a`: Boolean detection signal mapped from `SensorA AT %IX100.0`; enters A0 and feeds A1.
- `sensor_b`: Boolean detection signal mapped from `SensorB AT %IX100.1`; enters A0 and feeds A1.
- **Latched command**: internal information arrow from A1 to A2—not an additional plant I/O identifier.
- `conveyor`: Boolean run command produced by A2 and leaving A0, mapped to `Conveyor AT %QX100.0`.

The **output assignment rule** is `conveyor :=` the latched command. A1 sets that command when `sensor_a` is TRUE, resets it when `sensor_b` is TRUE, and otherwise retains its previous state. These detection signals are **inputs**, because they are processed into the command; the operating requirements and block semantics are **controls**, because they govern that processing.
