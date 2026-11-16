FUNCTION_BLOCK FB_FillingRuntime
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

(* Evaluate timers for the current GRAFCET situation. *)
filling_active := (active_state = 1);

filling_timer(IN := filling_active, PT := TON_Duration);
pause_timer(IN := filling_active, PT := TOF_Duration);

ton_q := filling_timer.Q;
tof_q := pause_timer.Q;

previous_state := active_state;

(* Fire at most one transition per invocation.
   Stop and level termination exclude all normal transitions. *)
CASE active_state OF
    0:
        IF start AND NOT stop AND NOT LSH AND NOT LSHH THEN
            active_state := 1;
        END_IF;

    1:
        IF stop OR LSH OR LSHH THEN
            active_state := 0;
        ELSIF ton_q AND NOT stop AND NOT LSH AND NOT LSHH THEN
            active_state := 2;
        END_IF;

    2:
        IF stop OR LSH OR LSHH THEN
            active_state := 0;
        ELSIF NOT tof_q AND NOT stop AND NOT LSH AND NOT LSHH THEN
            active_state := 1;
        END_IF;

ELSE
    active_state := 0;
END_CASE;

(* Synchronize timer inputs with any change in step activity.
   Leaving Filling resets TON and starts the TOF off-delay.
   Entering Filling starts TON and sets TOF.Q immediately. *)
IF active_state <> previous_state THEN
    filling_active := (active_state = 1);

    filling_timer(IN := filling_active, PT := TON_Duration);
    pause_timer(IN := filling_active, PT := TOF_Duration);

    ton_q := filling_timer.Q;
    tof_q := pause_timer.Q;
END_IF;

(* Continuous actions of the resulting GRAFCET situation. *)
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
    (* Commissioning defaults; adjust to the required process times. *)
    TON_Duration : TIME := T#5s;
    TOF_Duration : TIME := T#5s;

    start : BOOL := FALSE;
    stop : BOOL := FALSE;
    start_edge : R_TRIG;
    filling_runtime : FB_FillingRuntime;
END_VAR

(* Generate a one-scan start event, including while the cycle is active. *)
start_edge(CLK := StartCommand);
start := start_edge.Q;
stop := StopCommand;

filling_runtime(
    start := start,
    stop := stop,
    LSH := LSH,
    LSHH := LSHH,
    TON_Duration := TON_Duration,
    TOF_Duration := TOF_Duration
);

FillValve := filling_runtime.fill_valve;
DischargeValve := filling_runtime.discharge_valve;

END_PROGRAM
