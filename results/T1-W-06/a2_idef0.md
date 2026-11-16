The model below treats the **PLC control logic** as the system boundary: sensor signals are inputs, and the conveyor command is the output. **A0** is the context function; **A1–A3** are its child functions. Arrow names are noun phrases, and function names are verb phrases.

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control box transfer from A to B** | **sensor_a**; **sensor_b** | Start-on-A requirement; stop-and-hold-at-B requirement; IEC 61131-3 bistable requirement; I/O address mapping; reset-priority convention¹ | **conveyor** | OpenPLC Runtime; IEC 61131-3 RS function block; Modbus TCP connection to Factory I/O |
| A1 | Generate conveyor start request | **sensor_a** | Start-on-A requirement; input mapping `sensor_a` → `%IX100.0` | Start request | OpenPLC input image and program execution |
| A2 | Generate conveyor stop request | **sensor_b** | Stop-and-hold-at-B requirement; input mapping `sensor_b` → `%IX100.1` | Stop request | OpenPLC input image and program execution |
| A3 | Retain and issue conveyor command | Start request; stop request | IEC 61131-3 bistable requirement; reset-priority convention¹; output mapping `conveyor` → `%QX100.0` | **conveyor** | IEC 61131-3 RS function block; OpenPLC Runtime and output image; Modbus TCP output connection |

**Internal arrow connections**
- A1 **Start request** → A3 set input.
- A2 **Stop request** → A3 reset input.
- A3 **conveyor** → A0 boundary output.

The bistable memory keeps **conveyor** TRUE after **sensor_a** becomes FALSE, until **sensor_b** generates the stop request. With neither request active, the bistable retains its previous state.

¹ **Priority clarification:** The task does not explicitly define the simultaneous-sensor case. This model selects a reset-dominant **RS** block so that **sensor_b** keeps the conveyor stopped even if **sensor_a** is also TRUE. This supports the requirement that the box remain at B. The task does not specify a startup state.
