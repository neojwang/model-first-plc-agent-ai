FUNCTION_BLOCK FB_TimedTankFilling
VAR_INPUT
    StartCommand : BOOL;
    StopCommand : BOOL;
    LSH : BOOL;
    LSHH : BOOL;
    TON_Duration : TIME;
    TOF_Duration : TIME;
END_VAR
VAR_OUTPUT
    fill_valve : BOOL;
    discharge_valve : BOOL;
END_VAR
VAR
    StartEdge : R_TRIG;
    FillingTimer : TON;
    InterruptionTimer : TOF;
    ActiveState : INT := 0;
    start : BOOL;
    stop : BOOL;
    x0 : BOOL;
    x1 : BOOL;
    x2 : BOOL;
    ton_q : BOOL;
    tof_q : BOOL;
END_VAR

StartEdge(CLK := StartCommand);
start := StartEdge.Q;
stop := StopCommand;

x0 := (ActiveState = 0);
x1 := (ActiveState = 1);
x2 := (ActiveState = 2);

(* Both standard timers measure the activity of the filling step. *)
FillingTimer(IN := x1, PT := TON_Duration);
InterruptionTimer(IN := x1, PT := TOF_Duration);

ton_q := FillingTimer.Q;
tof_q := InterruptionTimer.Q;

IF stop THEN
    ActiveState := 0;
ELSE
    CASE ActiveState OF
        0:
            IF start AND NOT LSH THEN
                ActiveState := 1;
            END_IF;

        1:
            IF LSH THEN
                ActiveState := 0;
            ELSIF ton_q THEN
                ActiveState := 2;
            END_IF;

        2:
            IF LSH THEN
                ActiveState := 0;
            ELSIF NOT tof_q THEN
                ActiveState := 1;
            END_IF;

        ELSE
            ActiveState := 0;
    END_CASE;
END_IF;

x0 := (ActiveState = 0);
x1 := (ActiveState = 1);
x2 := (ActiveState = 2);

fill_valve := x1;
discharge_valve := FALSE;

(* LSHH is an observation only: the specified GRAFCET defines no LSHH transition. *)
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
    TankController : FB_TimedTankFilling;
    (* Configurable example presets; tune for the plant. *)
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
