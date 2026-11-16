FUNCTION_BLOCK FB_FillingTank
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
    CurrentState : INT := 0;
    start : BOOL;
    stop : BOOL;
    timer_done : BOOL;
END_VAR

StartEdge(CLK := StartCommand);
start := StartEdge.Q;
stop := StopCommand;

IF stop THEN
    CurrentState := 0;
ELSE
    CASE CurrentState OF
        0:
            IF start AND NOT LSHH THEN
                CurrentState := 1;
            END_IF;

        1:
            IF LSHH THEN
                CurrentState := 0;
            END_IF;

        ELSE
            CurrentState := 0;
    END_CASE;
END_IF;

FillingTimer(
    IN := (CurrentState = 1),
    PT := TimerDuration
);
timer_done := FillingTimer.Q;

IF (CurrentState = 1) AND timer_done THEN
    CurrentState := 0;
    (* Reset immediately so a subsequent start receives a fresh interval. *)
    FillingTimer(IN := FALSE, PT := TimerDuration);
END_IF;

fill_valve := (CurrentState = 1) AND NOT stop AND NOT LSHH;
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
    TankControl : FB_FillingTank;
END_VAR

TankControl(
    StartCommand := StartCommand,
    StopCommand := StopCommand,
    LSH := LSH,
    LSHH := LSHH,
    TimerDuration := TimerDuration
);

FillValve := TankControl.fill_valve;
DischargeValve := TankControl.discharge_valve;

END_PROGRAM
