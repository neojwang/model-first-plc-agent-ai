FUNCTION_BLOCK FillingRuntime
VAR_INPUT
    start : BOOL;
    stop : BOOL;
    LSH : BOOL;
    LSHH : BOOL;
    TimerDuration : TIME;
END_VAR
VAR_OUTPUT
    fill_valve : BOOL;
    discharge_valve : BOOL;
END_VAR
VAR
    x0 : BOOL := TRUE;
    x1 : BOOL := FALSE;
    timer_done : BOOL := FALSE;
    filling_timer : TON;
    t1 : BOOL;
    t2 : BOOL;
END_VAR

(* Measure the duration of the currently active filling step. *)
filling_timer(IN := x1, PT := TimerDuration);
timer_done := filling_timer.Q;

(* Evaluate both transitions against the same current situation. *)
t1 := x0 AND start AND NOT stop AND NOT LSHH;
t2 := x1 AND (stop OR timer_done OR LSHH);

IF t1 THEN
    x0 := FALSE;
    x1 := TRUE;

    (* Start a fresh timing interval on entry to x1. *)
    filling_timer(IN := TRUE, PT := TimerDuration);
    timer_done := FALSE;
ELSIF t2 THEN
    x0 := TRUE;
    x1 := FALSE;

    (* Reset the owned timer on leaving x1. *)
    filling_timer(IN := FALSE, PT := TimerDuration);
    timer_done := FALSE;
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
    (* Configure the required filling duration here. *)
    TimerDuration : TIME := T#10s;
    start_edge : R_TRIG;
    filling_control : FillingRuntime;
END_VAR

start_edge(CLK := StartCommand);

filling_control(
    start := start_edge.Q,
    stop := StopCommand,
    LSH := LSH,
    LSHH := LSHH,
    TimerDuration := TimerDuration
);

FillValve := filling_control.fill_valve;
DischargeValve := filling_control.discharge_valve;

END_PROGRAM
