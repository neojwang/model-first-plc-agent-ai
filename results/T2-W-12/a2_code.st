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
    ActiveState : INT := 0;
    start : BOOL;
    stop : BOOL;
    timer_done : BOOL;
END_VAR

StartEdge(CLK := StartCommand);
start := StartEdge.Q;
stop := StopCommand;

IF stop THEN
    ActiveState := 0;
ELSE
    CASE ActiveState OF
        0:
            IF start AND NOT LSHH THEN
                ActiveState := 1;
            END_IF;
        1:
            IF LSHH THEN
                ActiveState := 0;
            END_IF;
    ELSE
        ActiveState := 0;
    END_CASE;
END_IF;

(* Enable the timer immediately upon entry into the filling step. *)
FillingTimer(IN := (ActiveState = 1), PT := TimerDuration);
timer_done := FillingTimer.Q;

IF (ActiveState = 1) AND timer_done THEN
    ActiveState := 0;

    (* Reset the timer on exit, including before a possible next-scan start. *)
    FillingTimer(IN := FALSE, PT := TimerDuration);
    timer_done := FillingTimer.Q;
END_IF;

fill_valve := (ActiveState = 1);
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
    TankController : FB_TimedTank;
    (* Configurable timer preset; set to the required filling duration. *)
    TimerDuration : TIME := T#5s;
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
