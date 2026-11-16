## IDEF0 model

**Scope:** Control box transfer from sensor A to sensor B. The model boundary includes PLC sensing and command logic; the conveyor, box, and simulated plant remain external.

**Priority decision:** Use an IEC 61131-3 **RS bistable**, with reset priority. If both sensors are TRUE, the conveyor stops, giving the sensor B stopping requirement precedence.

The external signal identifiers are exactly **`sensor_a`**, **`sensor_b`**, and **`conveyor`**. *Set request* and *Reset request* below are internal information-flow arrows, not additional I/O identifiers.

### A0 — Context function

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| A0 | Control box transfer from A to B | `sensor_a`; `sensor_b` | Start-on-A requirement; Stop-at-B requirement; Command-retention requirement; Reset-priority rule; I/O address mapping | `conveyor` | OpenPLC Runtime; IEC 61131-3 RS bistable instance; Modbus TCP connection; Factory I/O slave interface |

### A0 decomposition — Child functions

| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| A1 | Determine the conveyor start request | `sensor_a` | Start-on-A requirement | Set request | OpenPLC Runtime |
| A2 | Determine the conveyor stop request | `sensor_b` | Stop-at-B requirement | Reset request | OpenPLC Runtime |
| A3 | Retain and issue the conveyor command | Set request; Reset request | Command-retention requirement; Reset-priority rule; I/O address mapping | `conveyor` | OpenPLC Runtime; IEC 61131-3 RS bistable instance; Modbus TCP connection; Factory I/O slave interface |

### Arrow definitions and routing

All arrow labels below are noun phrases or the required signal identifiers.

| Arrow | Source → Destination | Meaning |
|---|---|---|
| `sensor_a` | A0 input boundary → A1 | Box-presence indication at A; scene tag `SensorA`, mapped to `%IX100.0` |
| `sensor_b` | A0 input boundary → A2 | Box-presence indication at B; scene tag `SensorB`, mapped to `%IX100.1` |
| Set request | A1 → A3 | Level-sensitive start request, TRUE while `sensor_a` is TRUE |
| Reset request | A2 → A3 | Level-sensitive stop request, TRUE while `sensor_b` is TRUE |
| `conveyor` | A3 → A0 output boundary | Retained conveyor command; scene tag `Conveyor`, mapped to `%QX100.0`; TRUE runs the conveyor |
| Start-on-A requirement | A0 control boundary → A1 | Conveyor-start requirement upon detection at A |
| Stop-at-B requirement | A0 control boundary → A2 | Conveyor-stop requirement upon detection at B |
| Command-retention requirement | A0 control boundary → A3 | Command retention between sensor detections using a bistable |
| Reset-priority rule | A0 control boundary → A3 | Stop precedence during simultaneous start and stop requests |
| I/O address mapping | A0 control boundary → A3 | Output-address association for the conveyor command |

The mechanisms listed at A0 are allocated to the child functions as shown in their ICOM rows. No additional external inputs or outputs are introduced by the decomposition.

### Required command behavior

| `sensor_a` | `sensor_b` | Resulting `conveyor` behavior |
|---|---|---|
| FALSE | FALSE | Retain the previous command |
| TRUE | FALSE | Set TRUE |
| FALSE | TRUE | Reset FALSE |
| TRUE | TRUE | Reset FALSE |

Thus, departure from sensor A does not stop the conveyor: the RS instance retains the run command until sensor B requests a reset.

**Pre-implementation clarification:** Startup and restart initialization are not specified. An initially reset command (`conveyor` FALSE) is a sensible proposed policy, but it must be confirmed rather than treated as an existing requirement.
