Continue as the independent reviewer. Re-generate IEC 61131-3 Structured Text (ST) for OpenPLC from your own GRAFCET below: one PROGRAM Main that calls one FUNCTION_BLOCK, the I/O names of the control task, every variable declared, and the standard function blocks of IEC 61131-3 where the task names them. The code must compile with matiec, the strict IEC 61131-3 compiler of OpenPLC: declare located variables (AT %I..., %Q...) in a VAR block of their own; do not use keywords or names of standard functions (such as STEP, DT, MID) as identifiers or enumeration values; give every CASE branch at least one statement. Output only the code.

Control task:
{TASK_CARD}

Your GRAFCET (JSON):
{GRAFCET_JSON}
