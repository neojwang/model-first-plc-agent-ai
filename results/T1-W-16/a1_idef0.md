## A0 context model

**A0 — Transport a box from A to B**

The function starts the conveyor when `sensor_a` is TRUE, retains the running command after the box leaves A, and stops the conveyor when `sensor_b` becomes TRUE.

Use an IEC 61131-3 **reset-dominant RS bistable**. If both sensors are TRUE, the stop condition takes priority.

### ICOM table

In accordance with IDEF0, **inputs** are transformed by a function, **controls** govern its execution, **outputs** are its results, and **mechanisms** perform or support it.

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Transport a box from A to B** | `sensor_a`; `sensor_b` | Start-at-A requirement; stop-at-B requirement; command-retention requirement; reset-priority rule; I/O address mapping | `conveyor` | OpenPLC Runtime; IEC 61131-3 RS bistable; Modbus TCP connection; Factory I/O plant |
| **A1** | **Derive transport requests** | `sensor_a`; `sensor_b` | Start-at-A requirement; stop-at-B requirement; Boolean signal semantics | Start request; stop request | OpenPLC cyclic task |
| **A2** | **Retain the conveyor command** | Start request; stop request | Command-retention requirement; reset-priority rule; initial stopped-state policy | Retained conveyor command | IEC 61131-3 RS bistable; OpenPLC instance memory |
| **A3** | **Apply the conveyor command** | Retained conveyor command | I/O address mapping; output Boolean semantics | `conveyor` | OpenPLC output image; Modbus TCP connection; Factory I/O conveyor actuator |

### Child-function connections

```text
sensor_a ──┐
           ├──► A1 Derive transport requests
sensor_b ──┘           │
                      ├── Start request ──┐
                      └── Stop request ───┤
                                          ▼
                              A2 Retain the conveyor command
                                          │
                               Retained conveyor command
                                          │
                                          ▼
                              A3 Apply the conveyor command
                                          │
                                      conveyor
```

The parent inputs enter A1, and the parent output leaves A3. Parent controls and mechanisms are allocated to the child functions as shown in the table. **Start request**, **stop request**, and **retained conveyor command** are conceptual internal arrow names, not additional plant I/O identifiers.

## Control definitions

| Control arrow | Definition |
|---|---|
| Start-at-A requirement | A TRUE `sensor_a` produces an active start request. |
| Stop-at-B requirement | A TRUE `sensor_b` produces an active stop request. |
| Command-retention requirement | With neither request active, the bistable retains its previous command. |
| Reset-priority rule | An active stop request resets the command, including when the start request is also active. |
| Initial stopped-state policy | The command initially has the stopped state. This is a proposed initialization policy, since startup and restart behavior were not specified. |
| Boolean signal semantics | Each sensor is TRUE while a box is detected at its location. |
| Output Boolean semantics | TRUE runs the conveyor; FALSE stops it. |
| I/O address mapping | The scene tags are mapped to the specified OpenPLC addresses through the Factory I/O Modbus TCP driver. |

## Boundary arrow mapping

| Arrow name | Direction | OpenPLC address | Plant meaning |
|---|---|---|---|
| `sensor_a` | Input | `%IX100.0` | Box detection at A |
| `sensor_b` | Input | `%IX100.1` | Box detection at B |
| `conveyor` | Output | `%QX100.0` | Conveyor run command |

## Behavioral check

| `sensor_a` | `sensor_b` | Resulting `conveyor` |
|---|---|---|
| FALSE | FALSE | Previous command retained |
| TRUE | FALSE | TRUE |
| FALSE | TRUE | FALSE |
| TRUE | TRUE | FALSE — reset priority |

This model assumes that stopping the conveyor at B holds the box within B’s detection zone. It does not add an independent brake, position controller, or arrival lockout.
