FUNCTION_BLOCK FB_TimedFilling
VAR_INPUT
    StartCommand : BOOL;
    StopCommand : BOOL;
    LSH : BOOL;
    LSHH : BOOL;
    TimerDuration : TIME;
END_VAR
VAR_OUTPUT
    fill_valve : BOOL;
    discharge_valve : BOOL;
END_VAR
VAR
    StartEdge : R_TRIG;
    FillingTimer : TON;
    start : BOOL;
    stop : BOOL;
    timer_done : BOOL;
    x1 : BOOL := FALSE;
END_VAR

StartEdge(CLK := StartCommand);
start := StartEdge.Q;
stop := StopCommand;

IF stop THEN
    x1 := FALSE;
ELSIF NOT x1 AND start THEN
    x1 := TRUE;
END_IF;

FillingTimer(IN := x1, PT := TimerDuration);
timer_done := FillingTimer.Q;

IF x1 AND (stop OR timer_done OR LSHH) THEN
    x1 := FALSE;
    FillingTimer(IN := FALSE, PT := TimerDuration);
    timer_done := FillingTimer.Q;
END_IF;

fill_valve := x1 AND NOT stop;
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
    FillingController : FB_TimedFilling;
END_VAR

FillingController(
    StartCommand := StartCommand,
    StopCommand := StopCommand,
    LSH := LSH,
    LSHH := LSHH,
    TimerDuration := TimerDuration
);

FillValve := FillingController.fill_valve;
DischargeValve := FillingController.discharge_valve;

END_PROGRAM
