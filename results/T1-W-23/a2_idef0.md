| Node | Function | Inputs | Controls | Outputs | Mechanisms |
|---|---|---|---|---|---|
| **A0** | **Control box transfer from A to B** | `sensor_a`; `sensor_b` | Start-on-A requirement; stop-and-hold-at-B requirement; IEC 61131-3 bistable requirement; I/O mapping | `conveyor` | OpenPLC Runtime; IEC 61131-3 SR or RS function block; Modbus TCP connection; Factory I/O plant |
| **A1** | **Determine conveyor set and reset requests** | `sensor_a`; `sensor_b` | Start-on-A requirement; stop-at-B requirement | Set request; reset request | OpenPLC Boolean logic |
| **A2** | **Maintain the conveyor command state** | Set request; reset request | Bistable state-retention rule; reset-dominant priority¹ | Retained conveyor command | IEC 61131-3 **RS** function-block instance; persistent function-block state between PLC scans |
| **A3** | **Publish the conveyor command** | Retained conveyor command | Output mapping: `conveyor` → `%QX100.0`; TRUE = conveyor running | `conveyor` | OpenPLC output image; Modbus TCP connection; Factory I/O driver |

**Arrow definitions and decomposition connections**

- `sensor_a`: box-detection indication at A, mapped from `%IX100.0`; enters **A0** and **A1**.
- `sensor_b`: box-detection indication at B, mapped from `%IX100.1`; enters **A0** and **A1**.
- **Set request**: TRUE while `sensor_a` is TRUE; connects **A1 → A2**.
- **Reset request**: TRUE while `sensor_b` is TRUE; connects **A1 → A2**.
- **Retained conveyor command**: the RS block’s stored output; connects **A2 → A3**. With neither request active, its previous value is retained.
- `conveyor`: published conveyor command; leaves **A3** and the **A0** boundary.

¹ The task permits SR or RS but does not explicitly specify simultaneous-input priority. This model selects **reset-dominant RS**, so detection at B stops the conveyor even if A is also active. Startup initialization is not specified by the task.

The lowercase identifiers above are the prescribed external I/O names; the other arrow names describe internal information, not additional plant I/O. **A0** is the context function requested here; in strict FIPS 183 diagram numbering, the single context box numbered A0 appears on diagram **A-0**, and its decomposition is diagram **A0**.
