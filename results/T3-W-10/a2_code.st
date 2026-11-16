FUNCTION_BLOCK TankFillingController
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
    FillTimer : TON;
    PauseTimer : TOF;
    start : BOOL;
    stop : BOOL;
    ton_q : BOOL;
    tof_q : BOOL;
    ActiveState : INT := 0;
    FillingActive : BOOL;
END_VAR

StartEdge(CLK := StartCommand);
start := StartEdge.Q;
stop := StopCommand;

FillingActive := (ActiveState = 1);

FillTimer(
    IN := FillingActive,
    PT := TON_Duration
);
PauseTimer(
    IN := FillingActive,
    PT := TOF_Duration
);

ton_q := FillTimer.Q;
tof_q := PauseTimer.Q;

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

fill_valve := (ActiveState = 1) AND NOT stop;
discharge_valve := FALSE;

(* LSHH is a monitored plant input, not an additional GRAFCET
   receptivity. Avoiding LSHH requires adequate physical stopping
   margin above LSH; this controller does not establish that margin. *)

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
    Controller : TankFillingController;

    (* Configurable example presets; set to the required task values. *)
    TON_Duration : TIME := T#5s;
    TOF_Duration : TIME := T#5s;
END_VAR

Controller(
    StartCommand := StartCommand,
    StopCommand := StopCommand,
    LSH := LSH,
    LSHH := LSHH,
    TON_Duration := TON_Duration,
    TOF_Duration := TOF_Duration
);

FillValve := Controller.fill_valve;
DischargeValve := Controller.discharge_valve;

END_PROGRAM
