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
    PauseTimer : TOF;
    StateCode : INT := 0;
    FillingActive : BOOL;
    start : BOOL;
    stop : BOOL;
    ton_q : BOOL;
    tof_q : BOOL;
END_VAR

StartEdge(CLK := StartCommand);
start := StartEdge.Q;
stop := StopCommand;

(* Both timer inputs measure the activity of the filling step. *)
FillingActive := (StateCode = 1);
FillingTimer(IN := FillingActive, PT := TON_Duration);
PauseTimer(IN := FillingActive, PT := TOF_Duration);

ton_q := FillingTimer.Q;
tof_q := PauseTimer.Q;

(* Stop has priority over every normal transition. *)
IF stop THEN
    StateCode := 0;
ELSE
    CASE StateCode OF
        0:
            IF start AND NOT LSH THEN
                StateCode := 1;
            END_IF;

        1:
            IF LSH THEN
                StateCode := 0;
            ELSIF ton_q THEN
                StateCode := 2;
            END_IF;

        2:
            IF LSH THEN
                StateCode := 0;
            ELSIF NOT tof_q THEN
                StateCode := 1;
            END_IF;

        ELSE
            StateCode := 0;
    END_CASE;
END_IF;

(* LSHH is monitored by the interface; the supplied GRAFCET
   specifies no additional transition for this input. *)
fill_valve := (StateCode = 1) AND NOT stop;
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
    TankController : FB_TimedTankFilling;
    (* Configurable example presets; set to the required phase durations. *)
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
