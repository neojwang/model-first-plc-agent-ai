FUNCTION_BLOCK TankControl
VAR_INPUT
    start : BOOL;
    stop : BOOL;
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
    phase : INT := 0;
    filling_active : BOOL := FALSE;
    ton_q : BOOL := FALSE;
    tof_q : BOOL := FALSE;
    FillTimer : TON;
    PauseTimer : TOF;
END_VAR

(* Stop and level detection take priority over starting or filling. *)
IF stop OR LSH OR LSHH THEN
    phase := 0;
ELSIF (phase = 0) AND start THEN
    phase := 1;
END_IF;

filling_active := (phase = 1);

FillTimer(
    IN := filling_active,
    PT := TON_Duration
);
ton_q := FillTimer.Q;

PauseTimer(
    IN := filling_active,
    PT := TOF_Duration
);
tof_q := PauseTimer.Q;

CASE phase OF
    0:
        fill_valve := FALSE;

    1:
        IF ton_q THEN
            phase := 2;
        END_IF;

    2:
        IF NOT tof_q THEN
            phase := 1;
        END_IF;

ELSE
    phase := 0;
END_CASE;

fill_valve := (phase = 1) AND NOT stop AND NOT LSH AND NOT LSHH;
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
    (* Adjustable timer parameters; initial defaults are shown. *)
    TON_Duration : TIME := T#10s;
    TOF_Duration : TIME := T#5s;

    start : BOOL := FALSE;
    stop : BOOL := FALSE;
    StartEdge : R_TRIG;
    Controller : TankControl;
END_VAR

StartEdge(CLK := StartCommand);
start := StartEdge.Q;
stop := StopCommand;

Controller(
    start := start,
    stop := stop,
    LSH := LSH,
    LSHH := LSHH,
    TON_Duration := TON_Duration,
    TOF_Duration := TOF_Duration
);

FillValve := Controller.fill_valve;
DischargeValve := Controller.discharge_valve;

END_PROGRAM
