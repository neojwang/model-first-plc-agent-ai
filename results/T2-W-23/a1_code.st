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
    t1 : BOOL;
    t2 : BOOL;
    FillingTimer : TON;
END_VAR

FillingTimer(IN := x1, PT := TimerDuration);
timer_done := FillingTimer.Q;

t1 := x0 AND start AND NOT stop AND NOT LSHH AND NOT timer_done;
t2 := x1 AND (stop OR LSHH OR timer_done);

IF t1 THEN
    x0 := FALSE;
    x1 := TRUE;
ELSIF t2 THEN
    x0 := TRUE;
    x1 := FALSE;
END_IF;

IF t1 OR t2 THEN
    FillingTimer(IN := x1, PT := TimerDuration);
    timer_done := FillingTimer.Q;
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
    TimerDuration : TIME := T#10s;
    StartEdge : R_TRIG;
    FillingControl : FillingRuntime;
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
