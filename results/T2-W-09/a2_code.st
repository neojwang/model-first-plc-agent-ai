FUNCTION_BLOCK TankFillingController
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
    timer_done : BOOL := FALSE;
    x1 : BOOL := FALSE;
END_VAR

StartEdge(CLK := StartCommand);
start := StartEdge.Q;
stop := StopCommand;

IF NOT x1 THEN
    timer_done := FALSE;

    IF start AND NOT stop AND NOT LSHH AND NOT timer_done THEN
        x1 := TRUE;
    END_IF;
END_IF;

FillingTimer(IN := x1, PT := TimerDuration);
timer_done := FillingTimer.Q;

IF stop OR LSHH OR timer_done THEN
    x1 := FALSE;
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
    Controller : TankFillingController;
END_VAR

Controller(
    StartCommand := StartCommand,
    StopCommand := StopCommand,
    LSH := LSH,
    LSHH := LSHH,
    TimerDuration := TimerDuration
);

FillValve := Controller.fill_valve;
DischargeValve := Controller.discharge_valve;

END_PROGRAM
