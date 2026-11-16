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
    phase : INT := 0;
    filling_active : BOOL := FALSE;
    ton_q : BOOL := FALSE;
    tof_q : BOOL := FALSE;
    fill_timer : TON;
    pause_timer : TOF;
END_VAR

(* Stop and level switches have priority over all sequence transitions.
   LSHH is a backup interlock; normal filling ends at LSH. *)
IF stop OR LSH OR LSHH THEN
    phase := 0;
END_IF;

filling_active := (phase = 1);

fill_timer(IN := filling_active, PT := TON_Duration);
pause_timer(IN := filling_active, PT := TOF_Duration);

ton_q := fill_timer.Q;
tof_q := pause_timer.Q;

IF NOT stop AND NOT LSH AND NOT LSHH THEN
    CASE phase OF
        0:
            IF start THEN
                phase := 1;
            END_IF;

        1:
            IF ton_q THEN
                phase := 2;
            END_IF;

        2:
            IF NOT tof_q THEN
                phase := 1;
            END_IF;

        ELSE
            phase := 0;
    END_CASE;
END_IF;

fill_valve := (phase = 1) AND NOT stop AND NOT LSH AND NOT LSHH;
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
    (* Adjustable commissioning defaults. *)
    TON_Duration : TIME := T#5s;
    TOF_Duration : TIME := T#5s;
    start_edge : R_TRIG;
    tank : TankControl;
END_VAR

(* Evaluate the edge detector every scan, including while stopped. *)
start_edge(CLK := StartCommand);

tank(
    start := start_edge.Q,
    stop := StopCommand,
    LSH := LSH,
    LSHH := LSHH,
    TON_Duration := TON_Duration,
    TOF_Duration := TOF_Duration
);

FillValve := tank.fill_valve;
DischargeValve := tank.discharge_valve;

END_PROGRAM
