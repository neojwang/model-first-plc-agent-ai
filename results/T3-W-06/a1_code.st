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
    fill_valve : BOOL;
    discharge_valve : BOOL;
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

(* Both timers measure the activity of the filling step. *)
filling_active := active_state = 1;

filling_timer(IN := filling_active, PT := TON_Duration);
pause_timer(IN := filling_active, PT := TOF_Duration);

ton_q := filling_timer.Q;
tof_q := pause_timer.Q;

previous_state := active_state;

(* Evaluate transitions from the current situation only. *)
CASE active_state OF
    0:
        IF start AND NOT stop AND NOT LSH AND NOT LSHH THEN
            active_state := 1;
        END_IF;

    1:
        IF stop THEN
            active_state := 0;
        ELSIF LSH OR LSHH THEN
            active_state := 0;
        ELSIF ton_q THEN
            active_state := 2;
        END_IF;

    2:
        IF stop THEN
            active_state := 0;
        ELSIF LSH OR LSHH THEN
            active_state := 0;
        ELSIF NOT tof_q THEN
            active_state := 1;
        END_IF;

ELSE
    active_state := 0;
END_CASE;

(* Synchronize timer inputs with step activation/deactivation immediately.
   This starts the off-delay when the filling step is actually left and
   resets the on-delay before another filling phase can begin. *)
IF active_state <> previous_state THEN
    filling_active := active_state = 1;

    filling_timer(IN := filling_active, PT := TON_Duration);
    pause_timer(IN := filling_active, PT := TOF_Duration);

    ton_q := filling_timer.Q;
    tof_q := pause_timer.Q;
END_IF;

(* Continuous GRAFCET actions, evaluated after transition processing. *)
fill_valve := active_state = 1;
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
    (* Configurable presets; adjust to the required operating durations. *)
    TON_Duration : TIME := T#5s;
    TOF_Duration : TIME := T#5s;

    runtime_logic : FillingRuntime;
    initialized : BOOL := FALSE;
    previous_start_command : BOOL := FALSE;
    start : BOOL := FALSE;
END_VAR

(* A button held during startup does not constitute a new press. *)
IF NOT initialized THEN
    previous_start_command := StartCommand;
    initialized := TRUE;
END_IF;

start := StartCommand AND NOT previous_start_command;
previous_start_command := StartCommand;

runtime_logic(
    start := start,
    stop := StopCommand,
    LSH := LSH,
    LSHH := LSHH,
    TON_Duration := TON_Duration,
    TOF_Duration := TOF_Duration
);

FillValve := runtime_logic.fill_valve;
DischargeValve := runtime_logic.discharge_valve;

END_PROGRAM
