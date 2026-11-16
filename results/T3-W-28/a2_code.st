FUNCTION_BLOCK FB_TimedTankFilling
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
    sequence_state : INT := 0;
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

filling_active := (sequence_state = 1);

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
    sequence_state := 0;
ELSE
    CASE sequence_state OF
        0:
            IF start AND NOT LSH THEN
                sequence_state := 1;
            END_IF;

        1:
            IF LSH THEN
                sequence_state := 0;
            ELSIF ton_q THEN
                sequence_state := 2;
            END_IF;

        2:
            IF LSH THEN
                sequence_state := 0;
            ELSIF NOT tof_q THEN
                sequence_state := 1;
            END_IF;

        ELSE
            sequence_state := 0;
    END_CASE;
END_IF;

fill_valve := (sequence_state = 1);
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
    tank_controller : FB_TimedTankFilling;
    (* Commissioning defaults; configure for the plant. *)
    TON_Duration : TIME := T#5s;
    TOF_Duration : TIME := T#5s;
END_VAR

tank_controller(
    StartCommand := StartCommand,
    StopCommand := StopCommand,
    LSH := LSH,
    LSHH := LSHH,
    TON_Duration := TON_Duration,
    TOF_Duration := TOF_Duration
);

FillValve := tank_controller.fill_valve;
DischargeValve := tank_controller.discharge_valve;

END_PROGRAM
