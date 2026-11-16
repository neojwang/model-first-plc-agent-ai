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
    ActiveStep : INT := 0;
    start : BOOL := FALSE;
    stop : BOOL := FALSE;
    timer_done : BOOL := FALSE;
END_VAR

StartEdge(CLK := StartCommand);
start := StartEdge.Q;
stop := StopCommand;

IF stop THEN
    ActiveStep := 0;
ELSE
    CASE ActiveStep OF
        0:
            IF start AND NOT stop AND NOT LSHH AND NOT timer_done THEN
                ActiveStep := 1;
            END_IF;

        1:
            IF stop OR LSHH OR timer_done THEN
                ActiveStep := 0;
            END_IF;

    ELSE
        ActiveStep := 0;
    END_CASE;
END_IF;

(* Start timing in the same scan that activates the filling step. *)
FillingTimer(IN := (ActiveStep = 1), PT := TimerDuration);
timer_done := FillingTimer.Q;

(* Apply timer completion before writing the valve outputs. *)
IF (ActiveStep = 1) AND timer_done THEN
    ActiveStep := 0;
END_IF;

(* Reset the step-owned timer whenever the filling step is inactive. *)
IF ActiveStep = 0 THEN
    FillingTimer(IN := FALSE, PT := TimerDuration);
    timer_done := FillingTimer.Q;
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
    (* Configurable filling duration; adjust to the required setting. *)
    TimerDuration : TIME := T#10s;
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
