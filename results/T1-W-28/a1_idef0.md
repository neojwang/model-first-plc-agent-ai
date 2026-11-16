## IDEF0 scope and conventions

**A0 — Control box transfer from A to B**

The modeled boundary is the PLC control function. It receives the two sensor indications and produces the conveyor command; the conveyor and box are the controlled plant.

In FIPS 183 terminology, the **A-0 context diagram** contains function **A0**. The **A0 decomposition diagram** contains its children **A1–A3**.

**Priority decision:** Use a reset-dominant **RS** bistable. If both sensors are TRUE, the conveyor stops. This resolves a condition not explicitly prioritized in the requirements and supports keeping the box at sensor B.

## ICOM model

All function names are verb phrases. Arrow names are noun phrases; the required interface identifiers are preserved exactly.

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control box transfer from A to B** | `sensor_a`; `sensor_b` | Sensor detection semantics; I/O address mapping; Start-at-A rule; Stop-at-B rule; Bistable command requirement; Reset-priority policy | `conveyor` | OpenPLC Runtime; Factory I/O Modbus TCP interface; IEC 61131-3 RS bistable instance |
| **A1** | **Generate the start request** | `sensor_a` | Sensor detection semantics; I/O address mapping; Start-at-A rule | Start request | OpenPLC Runtime; Factory I/O Modbus TCP interface |
| **A2** | **Generate the stop request** | `sensor_b` | Sensor detection semantics; I/O address mapping; Stop-at-B rule | Stop request | OpenPLC Runtime; Factory I/O Modbus TCP interface |
| **A3** | **Retain the conveyor command** | Start request; Stop request | Bistable command requirement; Reset-priority policy; I/O address mapping | `conveyor` | OpenPLC Runtime; IEC 61131-3 RS bistable instance |

## Arrow definitions and routing

| Arrow | Meaning | Routing |
|---|---|---|
| `sensor_a` | Boolean indication that a box is detected at sensor A; mapped to **%IX100.0** | A0 input → A1 input |
| `sensor_b` | Boolean indication that a box is detected at sensor B; mapped to **%IX100.1** | A0 input → A2 input |
| Start request | Level-sensitive request to set the conveyor command while `sensor_a` is TRUE | A1 output → A3 input |
| Stop request | Level-sensitive request to reset the conveyor command while `sensor_b` is TRUE | A2 output → A3 input |
| `conveyor` | Boolean conveyor command; TRUE runs the conveyor and FALSE stops it; mapped to **%QX100.0** | A3 output → A0 output |
| Sensor detection semantics | TRUE indicates box presence at the corresponding sensor | A0 control → A1 and A2 controls |
| I/O address mapping | Binding of the required interface identifiers to the specified PLC addresses | A0 control → A1, A2, and A3 controls |
| Start-at-A rule | Box detection at sensor A requests conveyor operation | A0 control → A1 control |
| Stop-at-B rule | Box detection at sensor B requests conveyor stoppage | A0 control → A2 control |
| Bistable command requirement | Conveyor-command retention using an IEC 61131-3 SR or RS function block | A0 control → A3 control |
| Reset-priority policy | Stop request dominance over a simultaneous start request | A0 control → A3 control |

## Required behavior of A3

| Start request | Stop request | Resulting `conveyor` |
|---|---|---|
| FALSE | FALSE | Previous command retained |
| TRUE | FALSE | TRUE |
| FALSE | TRUE | FALSE |
| TRUE | TRUE | FALSE — reset dominates |

The retained command keeps the conveyor running after the box leaves sensor A and stops it when the box reaches sensor B. With neither request active afterward, the stopped command remains retained.

**Open design point:** Startup initialization is not specified. An initially FALSE conveyor command is recommended, but its cold-start and restart behavior should be confirmed before implementation.
