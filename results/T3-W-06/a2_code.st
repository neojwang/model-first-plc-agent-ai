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
    cycle_state : INT := 0;
    start_edge : R_TRIG;
    filling_timer : TON;
    pause_timer : TOF;
    start : BOOL;
    stop : BOOL;
    ton_q : BOOL;
    tof_q : BOOL;
    filling_active : BOOL;
END_VAR

start_edge(CLK := StartCommand);
start := start_edge.Q;
stop := StopCommand;

(* Both timers measure the activity of the filling step.
   TOF continues timing after that activity becomes FALSE. *)
filling_active := (cycle_state = 1);

filling_timer(
    IN := filling_active,
    PT := TON_Duration
);
pause_timer(
    IN := filling_active,
    PT := TOF_Duration
);

ton_q := filling_timer.Q;
tof_q := pause_timer.Q;

IF stop THEN
    cycle_state := 0;
ELSE
    CASE cycle_state OF
        0:
            IF start AND NOT LSH THEN
                cycle_state := 1;
            END_IF;

        1:
            IF LSH THEN
                cycle_state := 0;
            ELSIF ton_q THEN
                cycle_state := 2;
            END_IF;

        2:
            IF LSH THEN
                cycle_state := 0;
            ELSIF NOT tof_q THEN
                cycle_state := 1;
            END_IF;

        ELSE
            cycle_state := 0;
    END_CASE;
END_IF;

(* LSHH has no separate transition in the supplied GRAFCET. *)
fill_valve := (cycle_state = 1) AND NOT stop;
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
    controller : TankFillingController;
    (* Example presets; configure for the actual plant. *)
    TON_Duration : TIME := T#5s;
    TOF_Duration : TIME := T#5s;
END_VAR

controller(
    StartCommand := StartCommand,
    StopCommand := StopCommand,
    LSH := LSH,
    LSHH := LSHH,
    TON_Duration := TON_Duration,
    TOF_Duration := TOF_Duration
);

FillValve := controller.fill_valve;
DischargeValve := controller.discharge_valve;

END_PROGRAM
