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
    enter_fill : BOOL;
    timer_done : BOOL;
    filling_timer : TON;
END_VAR

(* Start timing in the scan that activates x1. *)
enter_fill := x0 AND start AND NOT stop AND NOT LSHH;

filling_timer(
    IN := x1 OR enter_fill,
    PT := TimerDuration
);

(* The owned condition is FALSE at the instant x1 becomes active. *)
timer_done := x1 AND filling_timer.Q;

(* Evaluate transitions from the current situation. *)
IF x0 THEN
    IF enter_fill THEN
        x0 := FALSE;
        x1 := TRUE;
    END_IF;
ELSIF x1 THEN
    IF stop OR LSHH OR timer_done THEN
        x1 := FALSE;
        x0 := TRUE;
    END_IF;
END_IF;

(* Reset the non-retentive timer whenever its owning step is inactive. *)
IF NOT x1 THEN
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
    (* Configurable filling duration. *)
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
