The model below treats the **PLC control logic** as the system boundary: sensor signals are inputs, and the conveyor command is the output. As requested, the top-level function is labeled **A0**; in IDEF0 notation, its context diagram is **A-0**, and its decomposition diagram is **A0**.

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control box transfer from A to B** | `sensor_a`; `sensor_b` | Start-on-A requirement; stop-at-B requirement; retained-command requirement; IEC 61131-3 SR-or-RS requirement; I/O address mapping | `conveyor` | OpenPLC Runtime; IEC 61131-3 bistable function block; Modbus TCP connection; Factory I/O scene interface |
| **A1** | **Generate start request** | `sensor_a` | Start-on-A requirement; input mapping `%IX100.0` | Start request | OpenPLC Runtime; input process image |
| **A2** | **Generate stop request** | `sensor_b` | Stop-at-B requirement; input mapping `%IX100.1` | Stop request | OpenPLC Runtime; input process image |
| **A3** | **Maintain conveyor command** | Start request; Stop request | Retained-command requirement; IEC 61131-3 SR-or-RS requirement; output mapping `%QX100.0` | `conveyor` | OpenPLC Runtime; IEC 61131-3 bistable function block; output process image |

**Functional interpretation**
- **A1:** An asserted `sensor_a` produces a start request.
- **A2:** An asserted `sensor_b` produces a stop request.
- **A3:** The start request sets the retained command; the stop request resets it. With neither request asserted, the bistable retains its state. Thus, the conveyor continues after the box leaves A and remains stopped after the stop request disappears, until another start request occurs.
- The internal arrows **Start request** and **Stop request** connect A1 and A2 to A3. The external signal names remain exactly `sensor_a`, `sensor_b`, and `conveyor`.

**Specification boundary:** The task does not define simultaneous detection at A and B or the initial retained state. SR and RS differ in simultaneous-request priority, so neither priority nor an initialization policy is added here as a requirement.
