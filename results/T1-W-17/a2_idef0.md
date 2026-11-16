The model below treats the **PLC conveyor-control logic** as the functional boundary. Thus, `sensor_a` and `sensor_b` are information inputs, and `conveyor` is the Boolean command output—not the physical conveyor or box.

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control box transfer from A to B** | `sensor_a`; `sensor_b` | Start-on-A requirement; stop-and-hold-at-B requirement; IEC 61131-3 bistable-block requirement; I/O mapping specification | `conveyor` | OpenPLC Runtime; IEC 61131-3 SR or RS function block; Modbus TCP connection to Factory I/O |
| **A1** | **Determine start request** | `sensor_a` | Start condition: a box detected at A requests conveyor operation | Start request | OpenPLC Boolean logic |
| **A2** | **Determine stop request** | `sensor_b` | Stop condition: a box detected at B requests conveyor stoppage | Stop request | OpenPLC Boolean logic |
| **A3** | **Maintain conveyor command** | Start request; Stop request | Bistable-state retention rule; start-on-A requirement; stop-and-hold-at-B requirement; selected block’s set/reset precedence | `conveyor` | IEC 61131-3 SR or RS function block executed by OpenPLC |

**Arrow connections and interpretation**

- A0 input `sensor_a` feeds A1; A0 input `sensor_b` feeds A2.
- A1’s **Start request** feeds A3’s set input; A2’s **Stop request** feeds A3’s reset input.
- A3’s retained Boolean state produces A0 output `conveyor`: TRUE runs the conveyor; FALSE stops it. With neither request active, the block retains its state.
- The I/O mapping specification binds `sensor_a` to `%IX100.0`, `sensor_b` to `%IX100.1`, and `conveyor` to `%QX100.0`.

The task does not explicitly specify simultaneous-request precedence or initialization. An **RS** block provides reset dominance if stopping at B must prevail when both sensors are TRUE; an **SR** block provides set dominance. This choice should be made explicit rather than silently assumed.
