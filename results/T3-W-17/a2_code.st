FUNCTION_BLOCK FB_TimedTank
VAR_INPUT
    StartCommand : BOOL;
    StopCommand : BOOL;
    LSH : BOOL;
    LSHH : BOOL;
    TON_Duration : TIME;
    TOF_Duration : TIME;
END_VAR
VAR_OUTPUT
    fill_valve : BOOL := FALSE;
    discharge_valve : BOOL := FALSE;
END_VAR
VAR
    CycleState : INT := 0;
    StartEdge : R_TRIG;
    FillTimer : TON;
    PauseTimer : TOF;
    start : BOOL;
    stop : BOOL;
    ton_q : BOOL;
    tof_q : BOOL;
    FillingActive : BOOL;
END_VAR

StartEdge(CLK := StartCommand);
start := StartEdge.Q;
stop := StopCommand;

FillingActive := (CycleState = 1);

(* Both timers measure the activity of the filling step. *)
FillTimer(IN := FillingActive, PT := TON_Duration);
PauseTimer(IN := FillingActive, PT := TOF_Duration);

ton_q := FillTimer.Q;
tof_q := PauseTimer.Q;

IF stop THEN
    CycleState := 0;
ELSE
    CASE CycleState OF
        0:
            IF start AND NOT LSH THEN
                CycleState := 1;
            END_IF;

        1:
            IF LSH THEN
                CycleState := 0;
            ELSIF ton_q THEN
                CycleState := 2;
            END_IF;

        2:
            IF LSH THEN
                CycleState := 0;
            ELSIF NOT tof_q THEN
                CycleState := 1;
            END_IF;

        ELSE
            CycleState := 0;
    END_CASE;
END_IF;

fill_valve := (CycleState = 1) AND NOT stop;
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
    (* Commissioning defaults; adjust for the plant. *)
    TON_Duration : TIME := T#5s;
    TOF_Duration : TIME := T#5s;
END_VAR

TankController(
    StartCommand := StartCommand,
    StopCommand := StopCommand,
    LSH := LSH,
    LSHH := LSHH,
    TON_Duration := TON_Duration,
    TOF_Duration := TOF_Duration
);

FillValve := TankController.fill_valve;
DischargeValve := TankController.discharge_valve;

END_PROGRAM
