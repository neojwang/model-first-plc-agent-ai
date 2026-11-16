FUNCTION_BLOCK FillingTankControl
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
    filling_active : BOOL;
    ton_q : BOOL;
    tof_q : BOOL;
    FillingTimer : TON;
    PauseTimer : TOF;
END_VAR

(* Phase 0: idle; phase 1: filling; phase 2: pause. *)
filling_active := (phase = 1);

FillingTimer(IN := filling_active, PT := TON_Duration);
PauseTimer(IN := filling_active, PT := TOF_Duration);

ton_q := FillingTimer.Q;
tof_q := PauseTimer.Q;

(* Stop and either level switch have priority over every transition.
   LSHH is an additional protective interlock. *)
IF stop OR LSH OR LSHH THEN
    phase := 0;
ELSE
    CASE phase OF
        0:
            IF start THEN
                phase := 1;
            END_IF;

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
END_IF;

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
    (* Configurable timing parameters. *)
    TON_Duration : TIME := T#5s;
    TOF_Duration : TIME := T#5s;

    start : BOOL;
    stop : BOOL;
    StartEdge : R_TRIG;
    TankController : FillingTankControl;
END_VAR

StartEdge(CLK := StartCommand);
start := StartEdge.Q;
stop := StopCommand;

TankController(
    start := start,
    stop := stop,
    LSH := LSH,
    LSHH := LSHH,
    TON_Duration := TON_Duration,
    TOF_Duration := TOF_Duration
);

FillValve := TankController.fill_valve;
DischargeValve := TankController.discharge_valve;

END_PROGRAM
