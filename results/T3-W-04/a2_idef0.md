| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control timed tank filling** | start; stop; LSH; LSHH | TON_Duration; TOF_Duration; initial-step rule; filling/pause sequence; stop priority; LSH termination rule; prohibition on reaching LSHH; discharge-valve inhibition | fill_valve; discharge_valve | OpenPLC Runtime; PLC program and scan cycle; Factory I/O tank simulation; Modbus TCP connection and mapped I/O |
| **A1** | **Determine the active operating step** | start; stop; LSH; LSHH; ton_q; tof_q; previous step activity | Step 0 initialization; transition rules stated below; stop priority; prohibition on reaching LSHH | Step activity: step 0, filling, or pause | PLC sequence logic; retained step-state memory |
| **A2** | **Generate filling and pause timing signals** | Filling-step activity | TON_Duration; TOF_Duration; TON semantics; TOF semantics; timer initialization rules | ton_q; tof_q | TON and TOF function-block instances; PLC time base and scan cycle |
| **A3** | **Set the valve commands** | Step activity; stop | fill_valve enabled only during filling; all outputs FALSE in step 0; stop override; discharge_valve always FALSE | fill_valve; discharge_valve | PLC output logic; mapped output image; Modbus TCP output transfer |

**Model interpretation and transition rules**

- **start** is the one-scan press event specified in the task, not a continuously held command. **stop**, **LSH**, and **LSHH** are Boolean input conditions.
- **A1** applies these rules:
  - Initially, select **step 0**.
  - From any step, **stop** selects step 0, overriding filling and pause behavior.
  - From step 0, **start AND NOT stop AND NOT LSH** selects filling. If LSH is already TRUE, filling remains inhibited.
  - While filling, **LSH** selects step 0; otherwise, **ton_q AND NOT LSH** selects pause.
  - While paused, **LSH** selects step 0; otherwise, **NOT tof_q AND NOT LSH** selects filling.
- **A2** supplies filling-step activity to both timer inputs. TON asserts **ton_q** after continuous filling for TON_Duration and resets when filling ends. TOF asserts **tof_q** while filling and maintains it for TOF_Duration after filling ends.
- **A3** sets **fill_valve** TRUE only when filling is active and **stop** is FALSE. **discharge_valve** remains FALSE.
- Internal arrows connect A1’s step activity to A2 and A3, and A2’s **ton_q** and **tof_q** back to A1. Step activity also feeds back to A1 as the previous state.

**LSHH qualification:** “LSHH must never be reached” is a safety constraint, not an explicitly specified additional transition. This model therefore does not invent an LSHH trip function. Compliance requires validating that stopping filling at LSH (2.4 m), including scan, communication, and valve-response delays, prevents the level from reaching LSHH (2.7 m).
