FUNCTION_BLOCK FB_TimedTank
VAR_INPUT
    StartCommand : BOOL;
    StopCommand : BOOL;
    LSH : BOOL;
    LSHH : BOOL;
    TimerDuration : TIME;
END_VAR
VAR_OUTPUT
    fill_valve : BOOL;
    discharge_valve : BOOL;
END_VAR
VAR
    start_edge : R_TRIG;
    filling_timer : TON;
    start : BOOL;
    stop : BOOL;
    timer_done : BOOL;
    active_state : INT := 0;
END_VAR

start_edge(CLK := StartCommand);
start := start_edge.Q;
stop := StopCommand;

(* Apply stop priority and the idle-to-filling transition. *)
IF stop THEN
    active_state := 0;
ELSE
    CASE active_state OF
        0:
            IF start AND NOT LSHH THEN
                active_state := 1;
            END_IF;
        1:
            IF LSHH THEN
                active_state := 0;
            END_IF;
    ELSE
        active_state := 0;
    END_CASE;
END_IF;

(* Start timing in the same scan that the filling step is entered. *)
filling_timer(
    IN := (active_state = 1),
    PT := TimerDuration
);
timer_done := filling_timer.Q;

IF (active_state = 1) AND (stop OR LSHH OR timer_done) THEN
    active_state := 0;

    (* Reset the owned timer immediately when its step is deactivated. *)
    filling_timer(IN := FALSE, PT := TimerDuration);
    timer_done := filling_timer.Q;
END_IF;

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
    (* Configure this parameter to the required filling duration. *)
    TimerDuration : TIME := T#0s;
    tank_controller : FB_TimedTank;
END_VAR

tank_controller(
    StartCommand := StartCommand,
    StopCommand := StopCommand,
    LSH := LSH,
    LSHH := LSHH,
    TimerDuration := TimerDuration
);

FillValve := tank_controller.fill_valve;
DischargeValve := tank_controller.discharge_valve;

END_PROGRAM
