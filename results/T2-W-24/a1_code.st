FUNCTION_BLOCK TankRuntime
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
    FillingTimer : TON;
    transition_start : BOOL;
    transition_finish : BOOL;
END_VAR

(* Evaluate the timer for the currently active situation. *)
FillingTimer(IN := x1, PT := TimerDuration);
timer_done := FillingTimer.Q;

(* Evaluate both transitions before changing the active situation. *)
transition_start := x0 AND start AND NOT stop AND NOT LSHH;
transition_finish := x1 AND (stop OR LSHH OR timer_done);

IF transition_finish THEN
    x0 := TRUE;
    x1 := FALSE;

    (* Reset the owned timer immediately on leaving x1. *)
    FillingTimer(IN := FALSE, PT := TimerDuration);
    timer_done := FALSE;

ELSIF transition_start THEN
    x0 := FALSE;
    x1 := TRUE;

    (* Start timing immediately on entering x1. *)
    FillingTimer(IN := TRUE, PT := TimerDuration);
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
    (* Configurable filling interval. *)
    TimerDuration : TIME := T#10s;
    StartEdge : R_TRIG;
    TankControl : TankRuntime;
END_VAR

StartEdge(CLK := StartCommand);

TankControl(
    start := StartEdge.Q,
    stop := StopCommand,
    LSH := LSH,
    LSHH := LSHH,
    TimerDuration := TimerDuration
);

FillValve := TankControl.fill_valve;
DischargeValve := TankControl.discharge_valve;

END_PROGRAM
