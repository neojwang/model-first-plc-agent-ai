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
    t1 : BOOL;
    t2 : BOOL;
    timer_done : BOOL;
    FillingTimer : TON;
END_VAR

(* Evaluate the entry transition from the current situation. *)
t1 := x0 AND start AND NOT stop AND NOT LSHH;

(* Start timing in the scan that activates the filling step. *)
FillingTimer(IN := x1 OR t1, PT := TimerDuration);

(* The owned condition is neutral when its step becomes active. *)
timer_done := x1 AND FillingTimer.Q;

(* Evaluate the return transition from the current situation. *)
t2 := x1 AND (stop OR timer_done OR LSHH);

(* Apply transitions simultaneously. *)
x0 := (x0 AND NOT t1) OR t2;
x1 := (x1 AND NOT t2) OR t1;

(* Reset the owned timer whenever its step is inactive. *)
IF NOT x1 THEN
    FillingTimer(IN := FALSE, PT := TimerDuration);
    timer_done := FALSE;
END_IF;

(* Non-stored actions of the resolved situation. *)
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
