## A0 context: Control box transfer from A to B

This is an **information/control model**: sensor indications enter the controller, and a conveyor command leaves it. The physical box is not an input arrow.

**Design decision:** Use a **reset-dominant RS bistable**. If both sensors are TRUE, the conveyor stops, giving the requirement to stop at B priority over the requirement to start at A.

### IDEF0 ICOM model

Every function has a verb-phrase name. Arrow labels are noun phrases; the external signal labels use the required identifiers exactly.

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control box transfer from A to B** | `sensor_a`; `sensor_b` | Start-at-A requirement; Stop-at-B requirement; Command-retention requirement; Reset-priority rule; I/O address mapping | `conveyor` | OpenPLC Runtime; IEC 61131-3 RS bistable instance; Modbus TCP connection; Factory I/O scene |
| **A1** | **Derive start and stop requests** | `sensor_a`; `sensor_b` | Start-at-A requirement; Stop-at-B requirement; Level-sensitive detection rule | Start request; Stop request | OpenPLC cyclic execution |
| **A2** | **Retain the conveyor command** | Start request; Stop request | Command-retention requirement; Reset-priority rule | Retained conveyor command | IEC 61131-3 RS bistable instance; OpenPLC cyclic execution |
| **A3** | **Publish the conveyor command** | Retained conveyor command | I/O address mapping; Boolean actuation convention | `conveyor` | OpenPLC output image; Modbus TCP connection; Factory I/O driver |

### Arrow connections and boundary balance

The child diagram preserves the A0 boundary: its only external data inputs are `sensor_a` and `sensor_b`, and its only external command output is `conveyor`.

| Arrow name | Source | Destination |
|---|---|---|
| `sensor_a` | A0 input boundary | A1 input |
| `sensor_b` | A0 input boundary | A1 input |
| Start request | A1 output | A2 input |
| Stop request | A1 output | A2 input |
| Retained conveyor command | A2 output | A3 input |
| `conveyor` | A3 output | A0 output boundary |
| Start-at-A requirement | A0 control boundary | A1 control |
| Stop-at-B requirement | A0 control boundary | A1 control |
| Level-sensitive detection rule | A0 sensor-detection requirements | A1 control |
| Command-retention requirement | A0 control boundary | A2 control |
| Reset-priority rule | A0 control boundary | A2 control |
| I/O address mapping | A0 control boundary | A3 control |
| Boolean actuation convention | A0 output specification | A3 control |

The **Level-sensitive detection rule** and **Boolean actuation convention** are refinements of the supplied sensor and output definitions, respectively—not additional plant behavior.

### Arrow definitions and I/O bindings

| Arrow name | Meaning or binding |
|---|---|
| `sensor_a` | BOOL indication from `SensorA AT %IX100.0`; TRUE while a box is detected at A |
| `sensor_b` | BOOL indication from `SensorB AT %IX100.1`; TRUE while a box is detected at B |
| Start request | Set request, asserted whenever `sensor_a` is TRUE |
| Stop request | Reset request, asserted whenever `sensor_b` is TRUE |
| Retained conveyor command | Stored RS bistable output |
| `conveyor` | BOOL command to `Conveyor AT %QX100.0`; TRUE runs the conveyor |

### Required bistable behavior

| Start request | Stop request | Retained conveyor command |
|---|---|---|
| FALSE | FALSE | Previous value |
| TRUE | FALSE | TRUE |
| FALSE | TRUE | FALSE |
| TRUE | TRUE | FALSE — reset priority |

Thus, detection at A starts the conveyor; the command remains set after the box leaves A; detection at B resets the command and stops the conveyor. Clearing B alone does not restart it.

**Initialization remains unspecified by the task.** The bistable’s startup value and warm-restart retention policy must be agreed before implementation; an initially stopped conveyor is the recommended default.
