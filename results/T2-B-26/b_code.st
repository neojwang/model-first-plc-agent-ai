FUNCTION_BLOCK FB_FillingTank
VAR_INPUT
    start : BOOL;
    stop : BOOL;
    LSH : BOOL;
    LSHH : BOOL;
    TimerDuration : TIME;
END_VAR
VAR_OUTPUT
    fill_valve : BOOL;
    discharge_valve : BOOL;
END_VAR
VAR
    current_state : INT := 0;
    filling_timer : TON;
    timer_done : BOOL := FALSE;
END_VAR

(* Stop has priority over all state transitions. *)
IF stop THEN
    current_state := 0;
ELSE
    CASE current_state OF
        0:
            IF start AND NOT LSHH THEN
                current_state := 1;
            END_IF;

        1:
            (* Remain filling until the timer or high-high switch trips. *)
            current_state := 1;

    ELSE
        current_state := 0;
    END_CASE;
END_IF;

(* Call the timer every scan, including while idle, to reset it. *)
filling_timer(
    IN := (current_state = 1) AND NOT stop AND NOT LSHH,
    PT := TimerDuration
);
timer_done := filling_timer.Q;

IF (current_state = 1) AND (timer_done OR LSHH) THEN
    current_state := 0;
END_IF;

fill_valve := (current_state = 1) AND NOT stop AND NOT LSHH;
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
    (* Configurable filling duration; default is ten seconds. *)
    TimerDuration : TIME := T#10s;
    start_edge : R_TRIG;
    tank_control : FB_FillingTank;
END_VAR

start_edge(CLK := StartCommand);

tank_control(
    start := start_edge.Q,
    stop := StopCommand,
    LSH := LSH,
    LSHH := LSHH,
    TimerDuration := TimerDuration
);

FillValve := tank_control.fill_valve;
DischargeValve := tank_control.discharge_valve;

END_PROGRAM
