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
    state_id : INT := 0;
    start_edge : R_TRIG;
    filling_ton : TON;
    filling_tof : TOF;
    start : BOOL;
    stop : BOOL;
    ton_q : BOOL;
    tof_q : BOOL;
    filling_active : BOOL;
END_VAR

(* Derive the one-scan start event, including while stopped. *)
start_edge(CLK := StartCommand);
start := start_edge.Q;
stop := StopCommand;

(* Both standard timers are driven by filling-step activity.
   Call each timer every scan so its internal state remains current. *)
filling_active := (state_id = 1);
filling_ton(IN := filling_active, PT := TON_Duration);
filling_tof(IN := filling_active, PT := TOF_Duration);
ton_q := filling_ton.Q;
tof_q := filling_tof.Q;

(* Evaluate at most one transition per scan. *)
IF stop THEN
    state_id := 0;
ELSE
    CASE state_id OF
        0:
            IF start AND NOT LSH THEN
                state_id := 1;
            END_IF;

        1:
            IF LSH THEN
                state_id := 0;
            ELSIF ton_q THEN
                state_id := 2;
            END_IF;

        2:
            IF LSH THEN
                state_id := 0;
            ELSIF NOT tof_q THEN
                state_id := 1;
            END_IF;

        ELSE
            state_id := 0;
    END_CASE;
END_IF;

(* LSHH is available for monitoring. The supplied GRAFCET
   specifies no additional transition for this signal. *)
fill_valve := (state_id = 1) AND NOT stop;
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
    (* Configurable example presets; adjust for the plant. *)
    TON_Duration : TIME := T#5s;
    TOF_Duration : TIME := T#2s;
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
