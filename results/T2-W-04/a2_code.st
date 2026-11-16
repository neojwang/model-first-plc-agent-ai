FUNCTION_BLOCK FB_TimedTank
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
    ActiveStep : INT := 0;
END_VAR

StartEdge(CLK := StartCommand);
start := StartEdge.Q;
stop := StopCommand;

IF stop THEN
    ActiveStep := 0;
ELSE
    CASE ActiveStep OF
        0:
            IF start THEN
                ActiveStep := 1;
            END_IF;
        1:
            ActiveStep := 1;
    ELSE
        ActiveStep := 0;
    END_CASE;
END_IF;

FillingTimer(IN := (ActiveStep = 1), PT := TimerDuration);
timer_done := FillingTimer.Q;

IF ActiveStep = 1 THEN
    IF stop OR timer_done OR LSHH THEN
        ActiveStep := 0;
        FillingTimer(IN := FALSE, PT := TimerDuration);
        timer_done := FillingTimer.Q;
    END_IF;
END_IF;

fill_valve := (ActiveStep = 1);
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
    TimerDuration : TIME;
    TankController : FB_TimedTank;
END_VAR

TankController(
    StartCommand := StartCommand,
    StopCommand := StopCommand,
    LSH := LSH,
    LSHH := LSHH,
    TimerDuration := TimerDuration
);

FillValve := TankController.fill_valve;
DischargeValve := TankController.discharge_valve;

END_PROGRAM
