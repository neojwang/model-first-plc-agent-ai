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
    state_id : INT := 0;
    filling_active : BOOL := FALSE;
    ton_q : BOOL := FALSE;
    tof_q : BOOL := FALSE;
    fill_timer : TON;
    pause_timer : TOF;
END_VAR

(* Stop and level switches override all operating states. *)
IF stop OR LSH OR LSHH THEN
    state_id := 0;
END_IF;

(* Invoke both timers every scan. *)
filling_active := (state_id = 1);

fill_timer(
    IN := filling_active,
    PT := TON_Duration
);
ton_q := fill_timer.Q;

pause_timer(
    IN := filling_active,
    PT := TOF_Duration
);
tof_q := pause_timer.Q;

IF NOT stop AND NOT LSH AND NOT LSHH THEN
    CASE state_id OF
        0:
            (* Idle: accept only a new StartCommand press. *)
            IF start THEN
                state_id := 1;
            END_IF;

        1:
            (* Filling: pause when the allowed filling time expires. *)
            IF ton_q THEN
                state_id := 2;
            END_IF;

        2:
            (* Paused: resume after the off-delay expires. *)
            IF NOT tof_q THEN
                state_id := 1;
            END_IF;

        ELSE
            state_id := 0;
    END_CASE;
END_IF;

fill_valve := (state_id = 1) AND NOT stop AND NOT LSH AND NOT LSHH;
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

    start : BOOL := FALSE;
    stop : BOOL := FALSE;
    start_edge : R_TRIG;
    controller : TankControl;
END_VAR

start_edge(CLK := StartCommand);
start := start_edge.Q;
stop := StopCommand;

controller(
    start := start,
    stop := stop,
    LSH := LSH,
    LSHH := LSHH,
    TON_Duration := TON_Duration,
    TOF_Duration := TOF_Duration
);

FillValve := controller.fill_valve;
DischargeValve := controller.discharge_valve;

END_PROGRAM
