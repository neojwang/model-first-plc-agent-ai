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
    state_number : INT := 0;
    filling_active : BOOL;
    fill_timer : TON;
    pause_timer : TOF;
    ton_q : BOOL;
    tof_q : BOOL;
END_VAR

(* Timer inputs follow the activity of the filling step. *)
filling_active := (state_number = 1);

fill_timer(
    IN := filling_active,
    PT := TON_Duration
);
pause_timer(
    IN := filling_active,
    PT := TOF_Duration
);

ton_q := fill_timer.Q;
tof_q := pause_timer.Q;

(* Stop and level switches have priority over normal transitions.
   LSHH provides an additional high-high shutdown interlock. *)
IF stop OR LSH OR LSHH THEN
    state_number := 0;
ELSE
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

fill_valve := (state_number = 1)
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
    (* Adjustable timer parameters. *)
    TON_Duration : TIME := T#5s;
    TOF_Duration : TIME := T#5s;

    start_edge : R_TRIG;
    controller : TankControl;
    start : BOOL;
    stop : BOOL;
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
