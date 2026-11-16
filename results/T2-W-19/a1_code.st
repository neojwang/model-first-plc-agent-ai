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
    FillingTimer : TON;
END_VAR

(* Evaluate the transition from the initial step. *)
IF x0 THEN
    IF start AND NOT stop AND NOT LSHH THEN
        x0 := FALSE;
        x1 := TRUE;
    END_IF;
END_IF;

(* Start timing in the scan in which the filling step becomes active. *)
FillingTimer(IN := x1, PT := TimerDuration);
timer_done := FillingTimer.Q;

(* Evaluate filling termination before assigning the physical outputs. *)
IF x1 THEN
    IF stop OR LSHH OR timer_done THEN
        x1 := FALSE;
        x0 := TRUE;

        (* Reset the step-owned timer immediately on leaving the step. *)
        FillingTimer(IN := FALSE, PT := TimerDuration);
        timer_done := FillingTimer.Q;
    END_IF;
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
    (* Configurable filling duration; adjust for the user scene. *)
    TimerDuration : TIME := T#10s;
    StartEdge : R_TRIG;
    RuntimeLogic : FillingRuntime;
END_VAR

StartEdge(CLK := StartCommand);

RuntimeLogic(
    start := StartEdge.Q,
    stop := StopCommand,
    LSH := LSH,
    LSHH := LSHH,
    TimerDuration := TimerDuration
);

FillValve := RuntimeLogic.fill_valve;
DischargeValve := RuntimeLogic.discharge_valve;

END_PROGRAM
