FUNCTION_BLOCK TankFillingRuntime
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
    t1 : BOOL;
    t2 : BOOL;
    timer_done : BOOL;
    FillingTimer : TON;
END_VAR

(* Evaluate the entry transition from the current situation. *)
t1 := x0 AND start AND NOT stop AND NOT LSHH;

(* Begin timing on entry and continue timing while x1 is active. *)
FillingTimer(IN := x1 OR t1, PT := TimerDuration);

(* The owned condition is neutral (FALSE) at activation of x1. *)
timer_done := x1 AND FillingTimer.Q;

(* Evaluate the return transition before changing the situation. *)
t2 := x1 AND (stop OR LSHH OR timer_done);

IF t1 THEN
    x0 := FALSE;
    x1 := TRUE;
ELSIF t2 THEN
    x0 := TRUE;
    x1 := FALSE;
END_IF;

(* Reset the non-retentive timer immediately when x1 is inactive. *)
IF NOT x1 THEN
    FillingTimer(IN := FALSE, PT := TimerDuration);
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
    (* Configurable filling-duration parameter. *)
    TimerDuration : TIME := T#5s;
    StartEdge : R_TRIG;
    FillingControl : TankFillingRuntime;
END_VAR

StartEdge(CLK := StartCommand);

FillingControl(
    start := StartEdge.Q,
    stop := StopCommand,
    LSH := LSH,
    LSHH := LSHH,
    TimerDuration := TimerDuration
);

FillValve := FillingControl.fill_valve;
DischargeValve := FillingControl.discharge_valve;

END_PROGRAM
