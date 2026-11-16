FUNCTION_BLOCK TankFillingControl
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
    current_state : INT := 0; (* 0: idle, 1: filling, 2: pause *)
    filling_active : BOOL;
    ton_q : BOOL;
    tof_q : BOOL;
    FillingTON : TON;
    FillingTOF : TOF;
END_VAR

filling_active := (current_state = 1)
                  AND NOT stop
                  AND NOT LSH
                  AND NOT LSHH;

FillingTON(IN := filling_active, PT := TON_Duration);
FillingTOF(IN := filling_active, PT := TOF_Duration);

ton_q := FillingTON.Q;
tof_q := FillingTOF.Q;

(* Stop and both level switches override all sequence transitions. *)
IF stop OR LSH OR LSHH THEN
    current_state := 0;
ELSE
    CASE current_state OF
        0:
            IF start THEN
                current_state := 1;
            END_IF;

        1:
            IF ton_q AND NOT LSH THEN
                current_state := 2;
            END_IF;

        2:
            IF NOT tof_q THEN
                current_state := 1;
            END_IF;

    ELSE
        current_state := 0;
    END_CASE;
END_IF;

fill_valve := (current_state = 1)
              AND NOT stop
              AND NOT LSH
              AND NOT LSHH;
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
    (* Configurable timer parameters. *)
    TON_Duration : TIME := T#5s;
    TOF_Duration : TIME := T#5s;

    StartEdge : R_TRIG;
    Controller : TankFillingControl;
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
