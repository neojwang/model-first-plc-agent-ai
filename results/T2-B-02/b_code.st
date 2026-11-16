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
    sequence_state : INT := 0;
    fill_timer : TON;
    timer_done : BOOL := FALSE;
END_VAR

(* Stop has priority over starting or continuing a fill cycle. *)
IF stop THEN
    sequence_state := 0;
ELSE
    CASE sequence_state OF
        0:
            IF start AND NOT LSHH THEN
                sequence_state := 1;
            END_IF;

        1:
            IF LSHH THEN
                sequence_state := 0;
            END_IF;

    ELSE
        sequence_state := 0;
    END_CASE;
END_IF;

(* Timing begins in the same scan that filling starts. *)
fill_timer(
    IN := (sequence_state = 1),
    PT := TimerDuration
);
timer_done := fill_timer.Q;

IF (sequence_state = 1) AND timer_done THEN
    sequence_state := 0;
END_IF;

fill_valve := (sequence_state = 1) AND NOT stop AND NOT LSHH;
discharge_valve := FALSE;

(* Reset immediately on completion so a new start can be accepted
   on the next scan without retaining the previous timer result. *)
IF sequence_state = 0 THEN
    fill_timer(IN := FALSE, PT := TimerDuration);
END_IF;

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
