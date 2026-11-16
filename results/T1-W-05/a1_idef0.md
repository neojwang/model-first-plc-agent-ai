## Model scope and design decision

The model covers the **PLC control function**, not the mechanical movement of the box. Sensor states enter the controller, and the conveyor command leaves it.

**Priority decision:** Use a **reset-dominant RS bistable**. If both sensors are TRUE, stopping at sensor B takes priority. This resolves a simultaneous-input condition not explicitly specified in the task.

## A0 context and child-function decomposition

Every function is named with a verb phrase. All ICOM entries name arrows using noun phrases; the required signal identifiers are preserved exactly.

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control box transfer from A to B** | `sensor_a`; `sensor_b` | Start-on-A requirement; stop-at-B requirement; command-retention requirement; reset-priority rule; I/O address mapping; IEC 61131-3 bistable requirement | `conveyor` | OpenPLC Runtime; Modbus TCP interface; Factory I/O scene; IEC 61131-3 RS bistable |
| **A1** | **Form the start request** | `sensor_a` | Start-on-A requirement; sensor A address mapping | Start request | OpenPLC input image; cyclic PLC execution |
| **A2** | **Form the stop request** | `sensor_b` | Stop-at-B requirement; sensor B address mapping | Stop request | OpenPLC input image; cyclic PLC execution |
| **A3** | **Retain and issue the conveyor command** | Start request; Stop request | Command-retention requirement; reset-priority rule; IEC 61131-3 bistable requirement; conveyor address mapping | `conveyor` | IEC 61131-3 RS bistable; OpenPLC output image; cyclic PLC execution |

### Arrow connections and boundary balancing

The A0 boundary arrows are preserved in the child decomposition:

- **`sensor_a`**: A0 input → A1 input.
- **`sensor_b`**: A0 input → A2 input.
- **Start request**: A1 output → A3 input.
- **Stop request**: A2 output → A3 input.
- **`conveyor`**: A3 output → A0 output.
- A0 control arrows are allocated to the applicable children as listed in the table.
- A0 mechanisms support the child functions through the PLC execution and I/O infrastructure.

### I/O address mapping

These mappings are control information for the model, not additional process signals.

| Model arrow | Direction | OpenPLC address | Factory I/O scene tag |
|---|---|---|---|
| `sensor_a` | Input | `%IX100.0` | SensorA |
| `sensor_b` | Input | `%IX100.1` | SensorB |
| `conveyor` | Output | `%QX100.0` | Conveyor |

### Functional meaning

- **A1:** The Start request is asserted while `sensor_a` is TRUE.
- **A2:** The Stop request is asserted while `sensor_b` is TRUE.
- **A3:** The Start request sets the retained command; the Stop request resets it. With neither request asserted, the previous command is retained. With both asserted, reset wins.
- A TRUE `conveyor` command runs the conveyor; FALSE stops it.

**Initialization assumption:** The retained command starts FALSE on initial startup. Warm-restart and retained-memory behavior require a separate project decision.
