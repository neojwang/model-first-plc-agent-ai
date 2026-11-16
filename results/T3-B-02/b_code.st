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
    state_no : INT := 0;
    filling_active : BOOL;
    ton_q : BOOL;
    tof_q : BOOL;
    FillTON : TON;
    FillTOF : TOF;
END_VAR

(* Timers are evaluated every scan using filling-step activity. *)
filling_active := (state_no = 1) AND NOT stop AND NOT LSH AND NOT LSHH;

FillTON(IN := filling_active, PT := TON_Duration);
FillTOF(IN := filling_active, PT := TOF_Duration);

ton_q := FillTON.Q;
tof_q := FillTOF.Q;

(* Stop and both level switches take priority over sequence transitions. *)
IF stop OR LSH OR LSHH THEN
    state_no := 0;
ELSE
    CASE state_no OF
        0:
            IF start THEN
                state_no := 1;
            END_IF;

        1:
            IF ton_q THEN
                state_no := 2;
            END_IF;

        2:
            IF NOT tof_q THEN
                state_no := 1;
            END_IF;

        ELSE
            state_no := 0;
    END_CASE;
END_IF;

fill_valve := (state_no = 1) AND NOT stop AND NOT LSH AND NOT LSHH;
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
    (* Configurable initial timer settings. *)
    TON_Duration : TIME := T#5s;
    TOF_Duration : TIME := T#5s;

    StartEdge : R_TRIG;
    Controller : TankControl;
END_VAR

StartEdge(CLK := StartCommand);

Controller(
    start := StartEdge.Q,
    stop := StopCommand,
    LSH := LSH,
    LSHH := LSHH,
    TON_Duration := TON_Duration,
    TOF_Duration := TOF_Duration
);

FillValve := Controller.fill_valve;
DischargeValve := Controller.discharge_valve;

END_PROGRAM
