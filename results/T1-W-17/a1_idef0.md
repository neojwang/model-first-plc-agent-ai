## Model scope and conventions

The model covers the **PLC control function**, not the physical movement of the box. Its boundary inputs are the two detection signals; its boundary output is the conveyor command.

All functions use verb phrases. All arrows use noun phrases. The required signal identifiers are used exactly:

| Arrow | Meaning | Address |
|---|---|---|
| `sensor_a` | Box detection at sensor A | `%IX100.0` |
| `sensor_b` | Box detection at sensor B | `%IX100.1` |
| `conveyor` | Conveyor run command | `%QX100.0` |

### Control policies

- **Transfer requirements:** Detection at A starts the conveyor; detection at B stops it.
- **Bistable requirement:** An IEC 61131-3 SR or RS function block retains the conveyor command.
- **Stop-priority policy:** Use a reset-dominant **RS** block so that `sensor_b` takes priority when both sensors are TRUE. This resolves a condition not explicitly specified in the task and supports keeping the box at B.
- **Startup policy:** Assume the retained conveyor command initializes to FALSE. This is a modeling assumption to confirm before implementation.
- **I/O mapping:** The signal-to-address assignments shown above.

## A0 context function

In standard IDEF0 notation, the **A-0 context diagram contains function A0**; the **A0 decomposition diagram contains A1–A3**.

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control conveyor transfer from A to B** | `sensor_a`; `sensor_b` | Transfer requirements; Bistable requirement; Stop-priority policy; Startup policy; I/O mapping | `conveyor` | OpenPLC Runtime; IEC 61131-3 RS function block; Modbus TCP connection; Factory I/O slave device |

## A0 decomposition

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A1** | **Acquire box detection signals** | `sensor_a`; `sensor_b` from the plant interface | I/O mapping | `sensor_a`; `sensor_b` in the PLC input image | OpenPLC Runtime; Modbus TCP connection; Factory I/O slave device |
| **A2** | **Retain the conveyor run command** | `sensor_a`; `sensor_b` from A1 | Transfer requirements; Bistable requirement; Stop-priority policy; Startup policy | `conveyor` as the retained run command | OpenPLC Runtime; IEC 61131-3 RS function block |
| **A3** | **Apply the conveyor run command** | `conveyor` from A2 | I/O mapping | `conveyor` at the plant interface | OpenPLC Runtime; Modbus TCP connection; Factory I/O slave device |

The acquisition and application functions preserve the signal names: they change the signal’s **representation or location**, not its logical meaning.

### Arrow routing

| Arrow | Source | Destination |
|---|---|---|
| `sensor_a` | A0 input boundary | A1 input |
| `sensor_b` | A0 input boundary | A1 input |
| `sensor_a` | A1 output | A2 input |
| `sensor_b` | A1 output | A2 input |
| `conveyor` | A2 output | A3 input |
| `conveyor` | A3 output | A0 output boundary |
| Transfer requirements | A0 control boundary | A2 control |
| Bistable requirement | A0 control boundary | A2 control |
| Stop-priority policy | A0 control boundary | A2 control |
| Startup policy | A0 control boundary | A2 control |
| I/O mapping | A0 control boundary | A1 and A3 controls |

Mechanism arrows enter the applicable functions from below, as listed in the ICOM tables.

## Behavioral contract for A2

The bistable state is internal to A2; it is not an additional external input.

| `sensor_a` | `sensor_b` | Resulting `conveyor` |
|---|---|---|
| FALSE | FALSE | Previous value retained |
| TRUE | FALSE | TRUE |
| FALSE | TRUE | FALSE |
| TRUE | TRUE | FALSE — reset priority |

Thus, the conveyor continues running after the box leaves A and stops when the box reaches B. No PLC code is introduced at this modeling stage.
