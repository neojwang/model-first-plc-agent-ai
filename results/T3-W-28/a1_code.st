FUNCTION_BLOCK FillingRuntime
VAR_INPUT
    start : BOOL;
    stop : BOOL;
    LSH : BOOL;
    LSHH : BOOL;
    TON_Duration : TIME;
    TOF_Duration : TIME;
END_VAR
VAR_OUTPUT
    fill_valve : BOOL;
    discharge_valve : BOOL;
END_VAR
VAR
    active_state : INT := 0;
    filling_active : BOOL;
    ton_timer : TON;
    tof_timer : TOF;
    ton_q : BOOL;
    tof_q : BOOL;
END_VAR

(* Evaluate both timers from the current filling-step activity. *)
filling_active := (active_state = 1);

ton_timer(IN := filling_active, PT := TON_Duration);
tof_timer(IN := filling_active, PT := TOF_Duration);

ton_q := ton_timer.Q;
tof_q := tof_timer.Q;

(* Evaluate transitions from the current situation only. *)
CASE active_state OF
    0:
        IF start AND NOT stop AND NOT LSH AND NOT LSHH THEN
            active_state := 1;
        END_IF;

    1:
        IF stop OR LSH OR LSHH THEN
            active_state := 0;
        ELSIF ton_q AND NOT stop AND NOT LSH AND NOT LSHH THEN
            active_state := 2;
        END_IF;

    2:
        IF stop OR LSH OR LSHH THEN
            active_state := 0;
        ELSIF NOT tof_q AND NOT stop AND NOT LSH AND NOT LSHH THEN
            active_state := 1;
        END_IF;

ELSE
    active_state := 0;
END_CASE;

(* Continuous actions of the resulting situation. *)
fill_valve := (active_state = 1);
discharge_valve := FALSE;

END_FUNCTION_BLOCK


PROGRAM Main
VAR
    StartCommand AT %IX100.0 : BOOL;
    StopCommand AT %IX100.1 : BOOL;
    LSH AT %IX100.2 : BOOL;
    LSHH AT %IX100.3 : BOOL;
    FillValve AT %QX100.0 : BOOL;
    DischargeValve AT %QX100.1 : BOOL;
END_VAR
VAR
    (* Configurable example presets. *)
    TON_Duration : TIME := T#5s;
    TOF_Duration : TIME := T#5s;
    start_edge : R_TRIG;
    runtime_logic : FillingRuntime;
END_VAR

start_edge(CLK := StartCommand);

runtime_logic(
    start := start_edge.Q,
    stop := StopCommand,
    LSH := LSH,
    LSHH := LSHH,
    TON_Duration := TON_Duration,
    TOF_Duration := TOF_Duration
);

FillValve := runtime_logic.fill_valve;
DischargeValve := runtime_logic.discharge_valve;

END_PROGRAM
