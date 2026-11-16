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
    current_state : INT := 0;
    filling_active : BOOL;
    filling_timer : TON;
    pause_timer : TOF;
    ton_q : BOOL;
    tof_q : BOOL;
END_VAR

(* Stop and level switches take priority over all state transitions. *)
IF stop OR LSH OR LSHH THEN
    current_state := 0;
END_IF;

filling_active := (current_state = 1);

filling_timer(
    IN := filling_active,
    PT := TON_Duration
);
ton_q := filling_timer.Q;

pause_timer(
    IN := filling_active,
    PT := TOF_Duration
);
tof_q := pause_timer.Q;

IF NOT stop AND NOT LSH AND NOT LSHH THEN
    CASE current_state OF
        0:
            IF start THEN
                current_state := 1;
            END_IF;

        1:
            IF ton_q THEN
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
    (* Adjustable parameters; default durations are five seconds. *)
    TON_Duration : TIME := T#5s;
    TOF_Duration : TIME := T#5s;

    start_edge : R_TRIG;
    start : BOOL;
    stop : BOOL;
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
