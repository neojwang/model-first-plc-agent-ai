Write IEC 61131-3 Structured Text (ST) for OpenPLC that implements exactly the GRAFCET below.

Structure: one PROGRAM Main (initialization and I/O handling) that calls one FUNCTION_BLOCK (the runtime logic). Use the I/O names of the control task for the program variables, declare every variable, and use the standard function blocks of IEC 61131-3 where the task names them. The code must compile with matiec, the strict IEC 61131-3 compiler of OpenPLC: declare located variables (AT %I..., %Q...) in a VAR block of their own; do not use keywords or names of standard functions (such as STEP, DT, MID) as identifiers or enumeration values; give every CASE branch at least one statement. Output only the code.

Control task:
{TASK_CARD}

GRAFCET (JSON):
{GRAFCET_JSON}
