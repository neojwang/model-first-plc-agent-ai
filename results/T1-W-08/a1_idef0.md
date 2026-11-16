## A0 context and decomposition

**Model boundary:** The model covers PLC control of the conveyor, from the Boolean sensor inputs to the Boolean conveyor output. Box motion and sensor detection belong to the Factory I/O plant.

**Priority decision:** Use a **reset-dominant RS bistable**. If both sensors are TRUE, the conveyor stops. This resolves simultaneous detection in favor of keeping the box at sensor B.

In the table, `sensor_a`, `sensor_b`, and `conveyor` are the exact external signal identifiers. Internal arrows have noun-phrase names.

### ICOM table

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control box transfer from A to B** | `sensor_a`; `sensor_b` | A-detection start requirement; B-detection stop requirement; command-retention requirement; reset-priority rule; IEC 61131-3 bistable requirement; I/O address mapping | `conveyor` | OpenPLC Runtime; IEC 61131-3 RS function block; Modbus TCP connection; Factory I/O slave device |
| **A1** | **Determine the start request** | `sensor_a` | A-detection start requirement; level-sensitive detection rule; input address mapping | Start request | OpenPLC Runtime; input process image |
| **A2** | **Determine the stop request** | `sensor_b` | B-detection stop requirement; level-sensitive detection rule; input address mapping | Stop request | OpenPLC Runtime; input process image |
| **A3** | **Retain the conveyor command** | Start request; Stop request | Command-retention requirement; reset-priority rule; IEC 61131-3 bistable requirement; output address mapping | `conveyor` | OpenPLC Runtime; IEC 61131-3 RS function block; output process image; Modbus TCP connection |

### Arrow connections

| Arrow | Source | Destination |
|---|---|---|
| `sensor_a` | A0 input boundary | A1 input |
| `sensor_b` | A0 input boundary | A2 input |
| Start request | A1 output | A3 input |
| Stop request | A2 output | A3 input |
| `conveyor` | A3 output | A0 output boundary |

Controls and mechanisms enter from the A0 boundary and are allocated to the child functions as shown in the ICOM table. Thus, the child model preserves the parent’s external inputs and output.

### Control-arrow definitions

| Control arrow | Meaning |
|---|---|
| A-detection start requirement | A TRUE `sensor_a` produces an active Start request. |
| B-detection stop requirement | A TRUE `sensor_b` produces an active Stop request. |
| Level-sensitive detection rule | Requests follow the current sensor levels; no edge detection is introduced. |
| Command-retention requirement | With neither request active, the bistable retains its previous command. |
| Reset-priority rule | An active Stop request overrides an active Start request. |
| IEC 61131-3 bistable requirement | Conveyor-command memory uses an IEC 61131-3 bistable function block; this model selects RS. |
| I/O address mapping | `sensor_a`: `%IX100.0`; `sensor_b`: `%IX100.1`; `conveyor`: `%QX100.0`. Factory I/O scene tags use these addresses through its Modbus TCP slave driver. |

### Required behavior of A3

| Start request | Stop request | Resulting `conveyor` |
|---|---|---|
| FALSE | FALSE | Previous command |
| TRUE | FALSE | TRUE |
| FALSE | TRUE | FALSE |
| TRUE | TRUE | FALSE |

This retention behavior keeps the conveyor running after the box leaves sensor A, until sensor B becomes TRUE. Once reset at B, the command remains FALSE after both requests become inactive.

**Initialization item:** The task does not specify the bistable’s startup state or restart-retention policy. Define these before implementation; an initial FALSE command is the recommended default.
