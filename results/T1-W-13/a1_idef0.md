## A0 — Control box transport from A to B

**Scope:** The PLC control function, including acquisition of the mapped sensor states, retention of the conveyor command, and application of that command to the scene. The physical transport of the box is performed by the plant.

All arrow labels below are noun phrases. The external signal identifiers are exactly **sensor_a**, **sensor_b**, and **conveyor**; address annotations are not part of their names.

### ICOM model

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control box transport from A to B** | **sensor_a** — box detection at A, `%IX100.0`; **sensor_b** — box detection at B, `%IX100.1` | **Start requirement** — detection at A starts transport; **Stop requirement** — detection at B stops transport; **Bistable requirement** — IEC 61131-3 SR or RS function block; **Stop-priority rule** — detection at B overrides detection at A; **I/O address mapping** | **conveyor** — conveyor run command, `%QX100.0` | **OpenPLC Runtime**; **Modbus TCP connection**; **Factory I/O slave device and conveyor plant** |
| **A1** | **Acquire box detection states** | **sensor_a** — mapped input state at `%IX100.0`; **sensor_b** — mapped input state at `%IX100.1` | **I/O address mapping**; **PLC input-update cycle** | **sensor_a** — acquired detection state; **sensor_b** — acquired detection state | **OpenPLC input image**; **Modbus TCP connection**; **Factory I/O sensor interface** |
| **A2** | **Retain the conveyor run command** | **sensor_a**; **sensor_b** | **Start requirement**; **Stop requirement**; **Bistable requirement**; **Stop-priority rule** | **Retained conveyor command** | **IEC 61131-3 RS function-block instance**; **Function-block state memory**; **OpenPLC execution engine** |
| **A3** | **Apply the conveyor run command** | **Retained conveyor command** | **I/O address mapping**; **PLC output-update cycle** | **conveyor** — mapped output state at `%QX100.0` | **OpenPLC output image**; **Modbus TCP connection**; **Factory I/O conveyor interface** |

### Child-function connections

```text
sensor_a ──► A1 ── sensor_a ──┐
                            ├──► A2 ── Retained conveyor command ──► A3 ──► conveyor
sensor_b ──► A1 ── sensor_b ──┘
```

The repeated **sensor_a** and **sensor_b** labels represent the same logical signals before and after acquisition, not additional signal identifiers. Controls enter the corresponding functions from above; mechanisms support them from below.

### Bistable behavior governing A2

Select a **reset-dominant RS** function block. This resolves simultaneous detection in favor of stopping the conveyor at B.

| sensor_a | sensor_b | Retained conveyor command |
|---|---|---|
| FALSE | FALSE | Previous command |
| TRUE | FALSE | TRUE |
| FALSE | TRUE | FALSE |
| TRUE | TRUE | FALSE |

Thus, detection at A starts the conveyor, the command remains set while the box travels between sensors, and detection at B resets the command. After reset, the conveyor remains stopped unless a subsequent detection at A sets it again.

**Open design point:** Startup initialization and power-cycle retention are not specified. They should be agreed before implementation; a FALSE startup command is the conservative default.
