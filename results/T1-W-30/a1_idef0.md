## IDEF0 scope and conventions

The model covers the **PLC control function**, with the conveyor and box transport as its external plant. In FIPS 183 notation, the context diagram is **A-0**, containing function **A0**; its decomposition is diagram **A0**, containing **A1–A3**.

**Design decision:** Use a reset-dominant IEC 61131-3 **RS** bistable. If both sensors are TRUE, stopping takes priority, so the conveyor remains stopped at sensor B.

## ICOM model

All function names are verb phrases; all arrow names are noun phrases. The identifiers `sensor_a`, `sensor_b`, and `conveyor` are used exactly as specified.

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control box transport from A to B** | `sensor_a`; `sensor_b` | Start-at-A requirement; Stop-at-B requirement; Reset-priority rule; Bistable-function requirement; I/O address mapping | `conveyor` | OpenPLC runtime; IEC 61131-3 RS bistable; Modbus TCP connection; Factory I/O slave device |
| **A1** | **Determine the start request** | `sensor_a` | Start-at-A requirement | Start request | OpenPLC runtime |
| **A2** | **Determine the stop request** | `sensor_b` | Stop-at-B requirement | Stop request | OpenPLC runtime |
| **A3** | **Maintain the conveyor command** | Start request; Stop request | Reset-priority rule; Bistable-function requirement; I/O address mapping | `conveyor` | OpenPLC runtime; IEC 61131-3 RS bistable; Modbus TCP connection; Factory I/O slave device |

### Control-arrow definitions

- **Start-at-A requirement:** A TRUE value of `sensor_a` produces an active Start request.
- **Stop-at-B requirement:** A TRUE value of `sensor_b` produces an active Stop request.
- **Reset-priority rule:** An active Stop request overrides an active Start request.
- **Bistable-function requirement:** The command retains its state when neither request is active; an IEC 61131-3 bistable supplies this memory.
- **I/O address mapping:**

  | Identifier | Address | Meaning |
  |---|---|---|
  | `sensor_a` | `%IX100.0` | Box detection at sensor A |
  | `sensor_b` | `%IX100.1` | Box detection at sensor B |
  | `conveyor` | `%QX100.0` | Conveyor run command |

## Child-function connections

```text
sensor_a ──► A1 Determine the start request ── Start request ──┐
                                                            ├──► A3 Maintain the conveyor command ──► conveyor
sensor_b ──► A2 Determine the stop request ─── Stop request ───┘
```

The parent controls are allocated to the child functions as shown in the ICOM table. The bistable’s retained state is internal to the A3 mechanism, rather than an additional external input.

## Behavioral interpretation

- Detection at A sets the command, starting the conveyor.
- After the box leaves A, the bistable keeps the conveyor running.
- Detection at B resets the command, stopping the conveyor.
- With neither sensor active, the previous command is retained.
- With both sensors active, the command is reset.

Startup initialization is not specified by the task and must be defined separately before implementation.
