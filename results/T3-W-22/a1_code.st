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
    previous_state : INT := 0;
    x0 : BOOL := TRUE;
    x1 : BOOL := FALSE;
    x2 : BOOL := FALSE;
    ton_q : BOOL := FALSE;
    tof_q : BOOL := FALSE;
    filling_timer : TON;
    pause_timer : TOF;
END_VAR

(* Evaluate timers using the current filling-step activity. *)
filling_timer(IN := x1, PT := TON_Duration);
pause_timer(IN := x1, PT := TOF_Duration);

ton_q := filling_timer.Q;
tof_q := pause_timer.Q;

previous_state := active_state;

(* Fire at most one transition per invocation. *)
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

x0 := active_state = 0;
x1 := active_state = 1;
x2 := active_state = 2;

(* Apply timer input edges immediately on step changes.
   In particular, leaving x1 starts the TOF interval and resets TON. *)
IF active_state <> previous_state THEN
    filling_timer(IN := x1, PT := TON_Duration);
    pause_timer(IN := x1, PT := TOF_Duration);
    ton_q := filling_timer.Q;
    tof_q := pause_timer.Q;
END_IF;

fill_valve := x1;
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
    (* Configurable commissioning values. *)
    TON_Duration : TIME := T#5s;
    TOF_Duration : TIME := T#5s;
    start : BOOL := FALSE;
    stop : BOOL := FALSE;
    start_edge : R_TRIG;
    controller : FillingRuntime;
END_VAR

start_edge(CLK := StartCommand);
start := start_edge.Q;
stop := StopCommand;

controller(
    start := start,
    stop := stop,
    LSH := LSH,
    LSHH := LSHH,
    TON_Duration := TON_Duration,
    TOF_Duration := TOF_Duration
);

FillValve := controller.fill_valve;
DischargeValve := controller.discharge_valve;

END_PROGRAM
