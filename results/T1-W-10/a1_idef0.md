## IDEF0 scope and conventions

**A0 — Control box transport from A to B**

The model covers the PLC control function. The conveyor, sensors, and box are the controlled plant; PLC code is not included.

- **Inputs** are detection information transformed into a conveyor command.
- **Controls** are the operating rules governing that transformation.
- **Outputs** are the resulting command information.
- **Mechanisms** are the resources implementing the functions.

**Priority decision:** Use a reset-dominant **RS** bistable. If both sensors are TRUE, stopping takes precedence. This resolves a simultaneous-detection case not explicitly specified in the task and supports keeping the box at B.

## ICOM model

All function names are verb phrases; all arrow names are noun phrases.

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control box transport from A to B** | `sensor_a`; `sensor_b` | Start-on-A rule; Stop-on-B rule; Bistable-command requirement; Reset-priority policy | `conveyor` | OpenPLC Runtime; IEC 61131-3 RS function block; Modbus TCP interface; Factory I/O scene |
| **A1** | **Form the start request** | `sensor_a` | Start-on-A rule | Start request | OpenPLC Runtime |
| **A2** | **Form the stop request** | `sensor_b` | Stop-on-B rule | Stop request | OpenPLC Runtime |
| **A3** | **Latch and reset the conveyor command** | Start request; Stop request | Bistable-command requirement; Reset-priority policy | `conveyor` | OpenPLC Runtime; IEC 61131-3 RS function block |

## Arrow definitions and connections

| Arrow name | Meaning | Connection |
|---|---|---|
| `sensor_a` | TRUE while a box is detected at A; mapped to `%IX100.0` | A0 input → A1 input |
| `sensor_b` | TRUE while a box is detected at B; mapped to `%IX100.1` | A0 input → A2 input |
| Start request | Level-sensitive request equal to the detection state at A | A1 output → A3 input |
| Stop request | Level-sensitive request equal to the detection state at B | A2 output → A3 input |
| `conveyor` | Retained conveyor command; TRUE runs the conveyor; mapped to `%QX100.0` | A3 output → A0 output |
| Start-on-A rule | Conveyor-start requirement upon detection at A | A0 control → A1 control |
| Stop-on-B rule | Conveyor-stop requirement upon detection at B | A0 control → A2 control |
| Bistable-command requirement | IEC 61131-3 bistable usage requirement | A0 control → A3 control |
| Reset-priority policy | Stop precedence during simultaneous start and stop requests | A0 control → A3 control |

The Factory I/O scene tags must be mapped to the stated addresses in its Modbus TCP driver, with Factory I/O acting as the slave device.

## Behavioral interpretation

- Detection at A generates the start request and sets the retained command.
- After the box leaves A, the RS block retains the running command.
- Detection at B generates the stop request and resets the command.
- With neither sensor active, the command retains its previous state.
- With both sensors active, reset dominance makes `conveyor` FALSE.

The RS block’s retained state is internal to **A3**, not an additional external arrow. Startup state and restart behavior are not specified by the task and should be confirmed before implementation.
