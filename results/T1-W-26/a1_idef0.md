## IDEF0 model

**Scope:** PLC control of the conveyor in Factory I/O Scene 2, “From A to B (Set and Reset).” As requested, **A0** is the context function; **A1–A3** form its decomposition.

**Design decision:** Use an IEC 61131-3 **RS bistable** with reset dominance. If both sensors are TRUE, the conveyor stops, giving sensor B priority. No additional restart interlock is introduced.

### ICOM table

Every function is named with a verb phrase. Arrow names are noun phrases; the external signal names use the required identifier vocabulary.

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control box transport from A to B** | `sensor_a`; `sensor_b` | Start-on-A requirement; Stop-at-B requirement; Bistable-memory requirement; Reset-priority policy; I/O address mapping | `conveyor` | OpenPLC Runtime; Modbus TCP connection; Factory I/O scene; Conveyor drive |
| **A1** | **Derive start and stop requests** | `sensor_a`; `sensor_b` | Start-on-A requirement; Stop-at-B requirement; Input address mapping | Start request; Stop request | OpenPLC input image; Cyclic PLC task |
| **A2** | **Retain the conveyor command** | Start request; Stop request | Bistable-memory requirement; Reset-priority policy | Retained conveyor command | IEC 61131-3 RS bistable instance; OpenPLC Runtime |
| **A3** | **Apply the conveyor command** | Retained conveyor command | Output address mapping; Conveyor actuation convention | `conveyor` | OpenPLC output image; Modbus TCP connection; Factory I/O conveyor drive |

### External arrow definitions and mapping

| Arrow | Meaning | Address |
|---|---|---|
| `sensor_a` | TRUE while a box is detected at sensor A | `%IX100.0` |
| `sensor_b` | TRUE while a box is detected at sensor B | `%IX100.1` |
| `conveyor` | TRUE to run the conveyor; FALSE to stop it | `%QX100.0` |

The Factory I/O driver maps the corresponding scene tags to these addresses. Factory I/O operates as the Modbus TCP slave device attached to OpenPLC.

### Child-function connections

- **A0 boundary → A1:** `sensor_a`, `sensor_b`
- **A1 → A2:** Start request, Stop request
- **A2 → A3:** Retained conveyor command
- **A3 → A0 boundary:** `conveyor`

The internal arrows are functional descriptions, not additional external I/O identifiers.

### Functional semantics

- **A1:** The Start request follows `sensor_a`; the Stop request follows `sensor_b`. These are level-sensitive requests, not edge pulses.
- **A2:** The RS bistable retains the conveyor command according to the following rules:

  | Start request | Stop request | Retained conveyor command |
  |---|---|---|
  | FALSE | FALSE | Previous command |
  | TRUE | FALSE | TRUE |
  | FALSE | TRUE | FALSE |
  | TRUE | TRUE | FALSE |

- **A3:** `conveyor` follows the Retained conveyor command.

Thus, detection at A starts the conveyor, the bistable maintains motion after the box leaves A, and detection at B resets the command and stops the conveyor. **Startup initialization is not specified by the task** and must be established before implementation.
