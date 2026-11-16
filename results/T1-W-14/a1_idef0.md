## Scope and modeling decisions

The model covers the **PLC control function**. The conveyor, box, and sensors form the external plant: sensor observations enter the controller, and the conveyor command leaves it.

- **A0** is the context function, shown on the IDEF0 **A-0 context diagram**.
- **A1–A3** are its child functions, shown on the **A0 decomposition diagram**.
- Use a **reset-dominant IEC 61131-3 RS bistable**. If both sensors are active, stopping takes priority so the box remains at B.
- All function names below are verb phrases; all arrow names are noun phrases.

## A0 context ICOM

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| A0 | Control box transfer from A to B | **sensor_a**; **sensor_b** | **Transfer rules**; **Reset-priority policy**; **IEC 61131-3 bistable requirement**; **I/O mapping specification** | **conveyor** | **OpenPLC Runtime**; **Modbus TCP connection**; **Factory I/O slave interface**; **RS bistable instance** |

### Context arrow definitions

| Arrow | Meaning |
|---|---|
| **sensor_a** | Boolean box detection at A; mapped to `%IX100.0`. |
| **sensor_b** | Boolean box detection at B; mapped to `%IX100.1`. |
| **conveyor** | Boolean conveyor command; mapped to `%QX100.0`. TRUE runs the conveyor; FALSE stops it. |
| **Transfer rules** | Detection at A starts transport; detection at B stops transport; the command remains latched between detections. |
| **Reset-priority policy** | Detection at B overrides detection at A when both are TRUE. |
| **IEC 61131-3 bistable requirement** | The conveyor command must be retained using an SR or RS function block; this model selects RS. |
| **I/O mapping specification** | The prescribed association between the scene tags, PLC addresses, and Boolean meanings. |

## A0 decomposition ICOM

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| A1 | Form transfer requests | **sensor_a**; **sensor_b** | **Transfer rules** | **Set request**; **Reset request** | **OpenPLC Runtime** |
| A2 | Retain conveyor command | **Set request**; **Reset request** | **Transfer rules**; **Reset-priority policy**; **IEC 61131-3 bistable requirement** | **Retained conveyor command** | **OpenPLC Runtime**; **RS bistable instance** |
| A3 | Apply conveyor command | **Retained conveyor command** | **I/O mapping specification** | **conveyor** | **OpenPLC Runtime**; **Modbus TCP connection**; **Factory I/O slave interface** |

### Internal arrow definitions

| Arrow | Meaning |
|---|---|
| **Set request** | Start request whose Boolean value equals **sensor_a**. |
| **Reset request** | Stop request whose Boolean value equals **sensor_b**. |
| **Retained conveyor command** | RS bistable output state, maintained between PLC scans and delivered to A3. |

### Functional connections

```text
sensor_a ─┐
          ├──► A1: Form transfer requests
sensor_b ─┘             │
                        ├── Set request ───┐
                        └── Reset request ─┤
                                          ▼
                              A2: Retain conveyor command
                                          │
                               Retained conveyor command
                                          │
                                          ▼
                               A3: Apply conveyor command
                                          │
                                       conveyor
```

Controls and mechanisms are listed in the ICOM tables rather than drawn in this simplified connectivity view.

## Required bistable behavior

| sensor_a | sensor_b | Retained conveyor command |
|---|---|---|
| FALSE | FALSE | Previous command state |
| TRUE | FALSE | TRUE |
| FALSE | TRUE | FALSE |
| TRUE | TRUE | FALSE — reset priority |

This behavior keeps the conveyor running after the box leaves A and stops it when the box reaches B. **Startup initialization is not specified by the task**; it must be resolved before implementation, with an initially stopped conveyor as the recommended default.
