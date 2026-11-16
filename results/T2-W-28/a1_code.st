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
    previous_x1 : BOOL;
    t1 : BOOL;
    t2 : BOOL;
    timer_done : BOOL := FALSE;
    FillingTimer : TON;
END_VAR

(* Update elapsed time for the currently active situation. *)
FillingTimer(IN := x1, PT := TimerDuration);
timer_done := FillingTimer.Q;

(* Evaluate both transitions using the same situation. *)
t1 := x0 AND start AND NOT stop AND NOT LSHH;
t2 := x1 AND (stop OR LSHH OR timer_done);

previous_x1 := x1;

IF t1 THEN
    x0 := FALSE;
    x1 := TRUE;
ELSIF t2 THEN
    x1 := FALSE;
    x0 := TRUE;
END_IF;

(* Start timing on entry and reset timing immediately on exit. *)
IF x1 <> previous_x1 THEN
    FillingTimer(IN := x1, PT := TimerDuration);
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
    (* Configurable filling-time parameter. *)
    TimerDuration : TIME := T#10s;
    StartEdge : R_TRIG;
    Controller : FillingRuntime;
END_VAR

StartEdge(CLK := StartCommand);

Controller(
    start := StartEdge.Q,
    stop := StopCommand,
    LSH := LSH,
    LSHH := LSHH,
    TimerDuration := TimerDuration
);

FillValve := Controller.fill_valve;
DischargeValve := Controller.discharge_valve;

END_PROGRAM
