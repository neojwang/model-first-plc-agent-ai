FUNCTION_BLOCK FB_TankFilling
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
    fillingTimer : TON;
    t1_enabled : BOOL;
    t2_enabled : BOOL;
END_VAR

(* Evaluate elapsed time for the currently active filling step. *)
fillingTimer(IN := x1, PT := TimerDuration);
timer_done := fillingTimer.Q;

(* Evaluate both transitions against the same current situation. *)
t1_enabled := x0 AND start AND NOT stop AND NOT LSHH;
t2_enabled := x1 AND (stop OR LSHH OR timer_done);

IF t1_enabled THEN
    x0 := FALSE;
    x1 := TRUE;
ELSIF t2_enabled THEN
    x1 := FALSE;
    x0 := TRUE;
END_IF;

(* Start timing on entry and reset timing on exit in this scan. *)
IF t1_enabled OR t2_enabled THEN
    fillingTimer(IN := x1, PT := TimerDuration);
    timer_done := fillingTimer.Q;
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
    (* Configurable filling-time parameter; adjust for the scene. *)
    TimerDuration : TIME := T#10s;
    startEdge : R_TRIG;
    tankControl : FB_TankFilling;
END_VAR

startEdge(CLK := StartCommand);

tankControl(
    start := startEdge.Q,
    stop := StopCommand,
    LSH := LSH,
    LSHH := LSHH,
    TimerDuration := TimerDuration
);

FillValve := tankControl.fill_valve;
DischargeValve := tankControl.discharge_valve;

END_PROGRAM
