**Scope:** The model covers the controller that commands the conveyor, not the physical movement of the box. Thus, `sensor_a` and `sensor_b` are inputs, and `conveyor` is the output. A0 is the context function; A1–A3 are its child functions.

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control box transfer from A to B** | `sensor_a`; `sensor_b` | Start-on-A requirement; stop-at-B requirement; IEC 61131-3 bistable requirement; I/O address mapping | `conveyor` | OpenPLC Runtime; IEC 61131-3 bistable function block; Modbus TCP connection to the Factory I/O slave device |
| **A1** | **Determine set and reset requests** | `sensor_a`; `sensor_b` | Start-on-A rule; stop-at-B rule; input mapping: `sensor_a` at `%IX100.0`, `sensor_b` at `%IX100.1` | Set request; reset request | OpenPLC input image and Boolean logic; Modbus TCP input interface |
| **A2** | **Maintain the conveyor run state** | Set request; reset request | IEC 61131-3 bistable requirement; state-retention rule; reset-priority rule | Retained run command | IEC 61131-3 **RS** function block executed by OpenPLC Runtime |
| **A3** | **Issue the conveyor command** | Retained run command | Output mapping: `conveyor` at `%QX100.0`; TRUE-to-run output convention | `conveyor` | OpenPLC output image; Modbus TCP output interface to Factory I/O |

**Functional interpretation**
- **A1:** The set request equals `sensor_a`; the reset request equals `sensor_b`.
- **A2:** A set request establishes the run state, a reset request clears it, and neither request leaves the previous state unchanged.
- **A3:** `conveyor` equals the retained run command.

**Priority choice:** The task permits SR or RS but does not explicitly define simultaneous detection. This model selects reset-dominant **RS**, so `sensor_b = TRUE` stops the conveyor even when `sensor_a` is also TRUE. The retained state is internal memory of the bistable, not an additional external input.
