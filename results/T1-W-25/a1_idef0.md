## Model scope and conventions

The model covers the PLC control of the conveyor; the box and conveyor are the controlled plant.

In FIPS 183 notation, the **A-0 context diagram contains function A0**. The **A0 decomposition diagram contains child functions A1–A3**.

- Functions are named with **verb phrases**.
- Arrows are named with **noun phrases**.
- The external signal names are exactly `sensor_a`, `sensor_b`, and `conveyor`.
- **Selected design rule:** use a reset-dominant IEC 61131-3 **RS** bistable. If both sensors are TRUE, stopping takes precedence. This resolves a case not explicitly prioritized in the requirements.
- Startup initialization is not specified by the task and must be defined before implementation.

## IDEF0 ICOM model

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control box transfer from A to B** | `sensor_a`; `sensor_b` | **Transfer requirements:** detection at A starts transport; detection at B stops transport; **State-retention requirement:** conveyor operation persists between sensors; **Bistable requirement:** IEC 61131-3 SR or RS function block; **Reset-priority rule**; **I/O mapping specification** | `conveyor` | **OpenPLC runtime**; **IEC 61131-3 RS instance**; **Modbus TCP interface**; **Factory I/O scene and conveyor actuator** |
| **A1** | **Determine start and stop requests** | `sensor_a`; `sensor_b` | **Sensor interpretation rules:** TRUE means box detected; **Request rules:** A detection supplies the set request, B detection supplies the reset request; **Input mapping specification** | **Set request**; **Reset request** | **OpenPLC input process image**; **Modbus TCP input exchange** |
| **A2** | **Retain the conveyor run command** | **Set request**; **Reset request** | **IEC 61131-3 RS semantics**; **Reset-priority rule**; **State-retention requirement** | **Retained run command** | **IEC 61131-3 RS instance**; **OpenPLC cyclic execution**; **Bistable state storage** |
| **A3** | **Apply the conveyor run command** | **Retained run command** | **Output interpretation rule:** TRUE runs the conveyor and FALSE stops it; **Output mapping specification** | `conveyor` | **OpenPLC output process image**; **Modbus TCP output exchange**; **Factory I/O conveyor actuator** |

## Arrow connections and boundary balancing

The child diagram preserves the A0 boundary: the two sensor inputs enter A1, the final `conveyor` output leaves A3, and the parent controls and mechanisms are allocated to the relevant children.

| Arrow | Source | Destination |
|---|---|---|
| `sensor_a` | A0 input boundary | A1 input |
| `sensor_b` | A0 input boundary | A1 input |
| **Set request** | A1 output | A2 input |
| **Reset request** | A1 output | A2 input |
| **Retained run command** | A2 output | A3 input |
| `conveyor` | A3 output | A0 output boundary |

The bistable’s retained state belongs inside A2; it is not an additional external input.

## I/O mapping specification

| Model arrow | Scene/PLC tag | OpenPLC address | Meaning of TRUE |
|---|---|---|---|
| `sensor_a` | SensorA | `%IX100.0` | Box detected at A |
| `sensor_b` | SensorB | `%IX100.1` | Box detected at B |
| `conveyor` | Conveyor | `%QX100.0` | Conveyor running |

Factory I/O is the Modbus TCP slave device; its driver must map the scene tags consistently with these OpenPLC addresses.

## Required behavior of A2

| Set request | Reset request | Retained run command |
|---|---|---|
| FALSE | FALSE | Previous command retained |
| TRUE | FALSE | TRUE |
| FALSE | TRUE | FALSE |
| TRUE | TRUE | FALSE — reset priority |

Thus, detection at A starts the conveyor, the command remains active while the box travels between sensors, and detection at B resets the command to stop the box there.
