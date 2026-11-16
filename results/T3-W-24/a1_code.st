FUNCTION_BLOCK FillingRuntime
VAR_INPUT
    start : BOOL;
    stop : BOOL;
    LSH : BOOL;
    LSHH : BOOL;
    TON_Duration : TIME;
    TOF_Duration : TIME;
END_VAR
VAR_OUTPUT
    fill_valve : BOOL := FALSE;
    discharge_valve : BOOL := FALSE;
END_VAR
VAR
    active_state : INT := 0;
    previous_state : INT := 0;
    filling_active : BOOL := FALSE;
    ton_q : BOOL := FALSE;
    tof_q : BOOL := FALSE;
    filling_timer : TON;
    pause_timer : TOF;
END_VAR

(* Update timers using the current GRAFCET situation.
   Both timer inputs are the activity of filling step x1. *)
filling_active := (active_state = 1);

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

previous_state := active_state;

(* Evaluate transitions from the current situation. *)
CASE active_state OF
    0:
        IF start AND NOT stop AND NOT LSH AND NOT LSHH THEN
            active_state := 1;
        END_IF;

    1:
        IF stop OR LSHH OR LSH THEN
            active_state := 0;
        ELSIF ton_q THEN
            active_state := 2;
        END_IF;

    2:
        IF stop OR LSHH OR LSH THEN
            active_state := 0;
        ELSIF NOT tof_q THEN
            active_state := 1;
        END_IF;

ELSE
    active_state := 0;
END_CASE;

(* Synchronize timer inputs with any step change in this scan.
   Leaving x1 resets TON and starts the TOF off-delay immediately.
   Entering x1 starts TON and makes TOF.Q TRUE immediately.
   No further transition is evaluated during this synchronization. *)
IF active_state <> previous_state THEN
    filling_active := (active_state = 1);

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
END_IF;

(* Continuous, non-stored GRAFCET actions. *)
fill_valve := (active_state = 1);
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
    (* Configurable presets; these initial values are commissioning defaults. *)
    TON_Duration : TIME := T#5s;
    TOF_Duration : TIME := T#5s;

    start : BOOL := FALSE;
    stop : BOOL := FALSE;
    start_edge : R_TRIG;
    filling_control : FillingRuntime;
END_VAR

(* Generate a one-scan start event from the physical button. *)
start_edge(CLK := StartCommand);
start := start_edge.Q;
stop := StopCommand;

filling_control(
    start := start,
    stop := stop,
    LSH := LSH,
    LSHH := LSHH,
    TON_Duration := TON_Duration,
    TOF_Duration := TOF_Duration
);

FillValve := filling_control.fill_valve;
DischargeValve := filling_control.discharge_valve;

END_PROGRAM
