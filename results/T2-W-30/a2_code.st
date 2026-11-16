FUNCTION_BLOCK FillingController
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
    SequenceState : INT := 0;
    start : BOOL;
    stop : BOOL;
    timer_done : BOOL;
END_VAR

StartEdge(CLK := StartCommand);
start := StartEdge.Q;
stop := StopCommand;

IF stop THEN
    SequenceState := 0;
ELSE
    CASE SequenceState OF
        0:
            IF start THEN
                SequenceState := 1;
            END_IF;
        1:
            IF LSHH THEN
                SequenceState := 0;
            END_IF;
    ELSE
        SequenceState := 0;
    END_CASE;
END_IF;

FillingTimer(
    IN := (SequenceState = 1),
    PT := TimerDuration
);
timer_done := FillingTimer.Q;

IF (SequenceState = 1) AND (stop OR LSHH OR timer_done) THEN
    SequenceState := 0;
END_IF;

IF SequenceState = 0 THEN
    FillingTimer(IN := FALSE, PT := TimerDuration);
    timer_done := FillingTimer.Q;
END_IF;

fill_valve := (SequenceState = 1);
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
    Controller : FillingController;
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
