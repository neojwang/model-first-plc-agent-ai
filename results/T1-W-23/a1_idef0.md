## A0 — Control box transfer from A to B

**Scope:** PLC control of the conveyor in Factory I/O Scene 2, “From A to B (Set and Reset).” The model transforms sensor indications into a retained conveyor command; it does not model the conveyor’s mechanical dynamics.

**Arbitration decision:** Use a **reset-dominant IEC 61131-3 RS bistable**. If both sensors are TRUE, stopping takes priority so that the conveyor does not move a box away from sensor B.

The context function is labeled **A0** as requested; in standard IDEF0 diagram numbering, its context diagram is **A-0**, and its decomposition diagram is **A0**.

### Context ICOM

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| A0 | Control box transfer from A to B | `sensor_a`; `sensor_b` | Start requirement at A; stop requirement at B; command-retention requirement; reset-dominance policy; I/O address mapping; IEC 61131-3 bistable requirement | `conveyor` | OpenPLC Runtime; IEC 61131-3 RS function block; Modbus TCP connection; Factory I/O scene and driver |

### Child-function ICOM

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| A1 | Derive start and stop requests | `sensor_a`; `sensor_b` | Sensor truth meanings; start requirement at A; stop requirement at B | Start request; stop request | OpenPLC cyclic execution; input process image |
| A2 | Retain the conveyor command | Start request; stop request; conveyor command state **(feedback)** | Command-retention requirement; reset-dominance policy; IEC 61131-3 bistable requirement | Conveyor command state | IEC 61131-3 RS function block; function-block instance memory; OpenPLC Runtime |
| A3 | Apply the conveyor command | Conveyor command state | I/O address mapping | `conveyor` | OpenPLC output process image; Modbus TCP connection; Factory I/O driver and conveyor actuator |

### Arrow connections

All arrow names are noun phrases. The external signal identifiers remain exactly as specified.

| Arrow | Source | Destination |
|---|---|---|
| `sensor_a` | A0 input boundary | A1 input |
| `sensor_b` | A0 input boundary | A1 input |
| Start request | A1 output | A2 input |
| Stop request | A1 output | A2 input |
| Conveyor command state | A2 output | A2 feedback input and A3 input |
| `conveyor` | A3 output | A0 output boundary |

The controls and mechanisms listed for the children are decompositions of the corresponding A0 boundary arrows.

### Control meanings

- **Start request:** TRUE while `sensor_a` is TRUE.
- **Stop request:** TRUE while `sensor_b` is TRUE.
- **Command-retention requirement:** With neither request active, the bistable retains its previous command.
- **Reset-dominance policy:** A stop request overrides a simultaneous start request.
- **I/O address mapping:**

| Boundary arrow | PLC address | Meaning |
|---|---|---|
| `sensor_a` | `%IX100.0` | Box detection at sensor A |
| `sensor_b` | `%IX100.1` | Box detection at sensor B |
| `conveyor` | `%QX100.0` | Conveyor run command |

**Startup assumption requiring confirmation:** Initialize the conveyor command state to FALSE. The task does not specify startup or restart retention behavior.
