## Model scope and decisions

The model covers **conveyor command control**, not physical box movement. The external signal arrows use exactly the identifiers `sensor_a`, `sensor_b`, and `conveyor`.

- **Bistable selection:** IEC 61131-3 **RS**, with reset dominance. If both sensors are TRUE, the conveyor stops.
- **State retention:** Once started, the conveyor continues running after the box leaves sensor A, until sensor B becomes TRUE.
- **Initialization assumption:** The retained command starts FALSE. Startup and restart initialization must be confirmed during implementation.

## A0 context and child decomposition

In IDEF0 terminology, the **A-0 context diagram** contains function **A0**. The **A0 decomposition diagram** contains child functions **A1–A3**.

Every function below has a verb-phrase name; all arrow labels are noun phrases.

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control conveyor transport from A to B** | `sensor_a`; `sensor_b` | Start-on-A requirement; Stop-on-B requirement; Command-retention requirement; Reset-priority rule; Initial-off assumption; I/O mapping specification | `conveyor` | OpenPLC Runtime; IEC 61131-3 RS function-block instance; Factory I/O Modbus TCP interface |
| **A1** | **Determine the start request** | `sensor_a` | Start-on-A requirement; Sensor-A mapping specification | Start request | OpenPLC Runtime |
| **A2** | **Determine the stop request** | `sensor_b` | Stop-on-B requirement; Sensor-B mapping specification | Stop request | OpenPLC Runtime |
| **A3** | **Maintain the conveyor command** | Start request; Stop request | Command-retention requirement; Reset-priority rule; Initial-off assumption; Conveyor mapping specification | `conveyor` | OpenPLC Runtime; IEC 61131-3 RS function-block instance; Persistent instance memory; Factory I/O Modbus TCP interface |

**Internal arrows:** *Start request* and *Stop request* are model-level information flows, not additional external I/O identifiers.

## Arrow connections and boundary balance

| Arrow | Source | Destination |
|---|---|---|
| `sensor_a` | A0 input boundary | A1 input |
| `sensor_b` | A0 input boundary | A2 input |
| Start request | A1 output | A3 input |
| Stop request | A2 output | A3 input |
| `conveyor` | A3 output | A0 output boundary |

A0’s controls and mechanisms are distributed to the child functions as listed in the ICOM table. The three external signal arrows are preserved across the decomposition boundary.

## Required behavior of A3

| Stop request | Start request | Resulting `conveyor` |
|---|---|---|
| TRUE | Either value | FALSE |
| FALSE | TRUE | TRUE |
| FALSE | FALSE | Previous retained value |

Thus, sensor B clears the retained command. When sensor B subsequently becomes FALSE, the conveyor remains stopped unless sensor A supplies another start request.

## I/O mapping controls

| Model identifier | Scene / PLC tag | OpenPLC address | Meaning |
|---|---|---|---|
| `sensor_a` | SensorA | `%IX100.0` | TRUE while a box is detected at A |
| `sensor_b` | SensorB | `%IX100.1` | TRUE while a box is detected at B |
| `conveyor` | Conveyor | `%QX100.0` | TRUE runs the conveyor |

Factory I/O is the Modbus TCP slave device; its driver mapping must associate these scene tags with the specified addresses.
