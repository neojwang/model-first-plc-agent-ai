The model below treats the function being modeled as the **PLC control of the conveyor**, rather than the physical transport of the box. Thus, `sensor_a` and `sensor_b` are information inputs, and `conveyor` is the commanded output.

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control box transfer from A to B** | `sensor_a`; `sensor_b` | Start-on-A requirement; stop-at-B requirement; IEC 61131-3 bistable requirement; I/O address mapping | `conveyor` | OpenPLC Runtime; IEC 61131-3 bistable function block; Modbus TCP connection; Factory I/O scene |
| **A1** | **Determine the start request** | `sensor_a` | Start-on-A requirement: a TRUE detection at A requests conveyor operation | Start request | OpenPLC input-processing logic |
| **A2** | **Determine the stop request** | `sensor_b` | Stop-at-B requirement: a TRUE detection at B requests conveyor stoppage | Stop request | OpenPLC input-processing logic |
| **A3** | **Maintain the conveyor command** | Start request; stop request; retained command state | IEC 61131-3 bistable requirement; reset-priority rule; output address mapping | `conveyor`; retained command state | OpenPLC Runtime; reset-dominant **RS** function block; Modbus TCP output interface |

**Arrow connections and interpretation**

- A0 input `sensor_a` feeds A1; A0 input `sensor_b` feeds A2.
- A1’s **Start request** and A2’s **Stop request** feed A3.
- A3’s **retained command state** is internal feedback to A3; it is not an additional external I/O signal.
- A3’s `conveyor` is the A0 output.
- The address mapping is `sensor_a` → `%IX100.0`, `sensor_b` → `%IX100.1`, and `conveyor` → `%QX100.0`.

A **reset-dominant RS** block is selected so that detection at B stops the conveyor even if both sensors are TRUE. With neither request active, the block retains its command. In Boolean form:

\[
\text{conveyor}_{next}
=
(\text{sensor\_a}\lor\text{conveyor}_{previous})
\land\neg\text{sensor\_b}.
\]

The task does not specify the initial retained state or restart behavior; these remain implementation decisions rather than additional requirements in this model.
