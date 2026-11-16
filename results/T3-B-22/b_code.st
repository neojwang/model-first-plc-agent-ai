FUNCTION_BLOCK FillingControl
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
    state_number : INT := 0;
    filling_active : BOOL;
    ton_q : BOOL;
    tof_q : BOOL;
    FillOnDelay : TON;
    FillOffDelay : TOF;
END_VAR

(* Stop and level switches take priority over normal sequencing. *)
IF stop OR LSH OR LSHH THEN
    state_number := 0;
END_IF;

filling_active := (state_number = 1);

FillOnDelay(IN := filling_active, PT := TON_Duration);
FillOffDelay(IN := filling_active, PT := TOF_Duration);

ton_q := FillOnDelay.Q;
tof_q := FillOffDelay.Q;

IF NOT (stop OR LSH OR LSHH) THEN
    CASE state_number OF
        0:
            IF start THEN
                state_number := 1;
            END_IF;

        1:
            IF ton_q THEN
                state_number := 2;
            END_IF;

        2:
            IF NOT tof_q THEN
                state_number := 1;
            END_IF;

        ELSE
            state_number := 0;
    END_CASE;
END_IF;

fill_valve := (state_number = 1) AND NOT stop AND NOT LSH AND NOT LSHH;
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
    (* Adjustable timing parameters. *)
    TON_Duration : TIME := T#5s;
    TOF_Duration : TIME := T#5s;

    start : BOOL;
    stop : BOOL;
    fill_valve : BOOL;
    discharge_valve : BOOL;

    StartEdge : R_TRIG;
    TankControl : FillingControl;
END_VAR

StartEdge(CLK := StartCommand);
start := StartEdge.Q;
stop := StopCommand;

TankControl(
    start := start,
    stop := stop,
    LSH := LSH,
    LSHH := LSHH,
    TON_Duration := TON_Duration,
    TOF_Duration := TOF_Duration
);

fill_valve := TankControl.fill_valve;
discharge_valve := TankControl.discharge_valve;

FillValve := fill_valve;
DischargeValve := discharge_valve;

END_PROGRAM
