FUNCTION_BLOCK FB_FillingTank
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
    current_state : INT := 0;
    filling_active : BOOL;
    ton_q : BOOL;
    tof_q : BOOL;
    fill_timer : TON;
    pause_timer : TOF;
END_VAR

(* Stop and either level switch take priority over starting or filling.
   LSHH is an additional fail-safe shutdown input. *)
IF stop OR LSH OR LSHH THEN
    current_state := 0;
ELSIF (current_state = 0) AND start THEN
    current_state := 1;
END_IF;

filling_active := (current_state = 1);

fill_timer(
    IN := filling_active,
    PT := TON_Duration
);
ton_q := fill_timer.Q;

(* End the filling phase as soon as TON expires. *)
IF (current_state = 1) AND ton_q THEN
    current_state := 2;
END_IF;

(* Calling TOF after the filling-to-pause transition starts its
   off-delay in the same scan that the fill valve closes. *)
filling_active := (current_state = 1);

pause_timer(
    IN := filling_active,
    PT := TOF_Duration
);
tof_q := pause_timer.Q;

CASE current_state OF
    0:
        fill_valve := FALSE;

    1:
        fill_valve := TRUE;

    2:
        fill_valve := FALSE;
        IF NOT tof_q THEN
            (* Resume on the next scan, keeping this scan's output off.
               TON has already been reset during this pause scan. *)
            current_state := 1;
        END_IF;

ELSE
    current_state := 0;
    fill_valve := FALSE;
END_CASE;

discharge_valve := FALSE;

IF stop OR LSH OR LSHH THEN
    current_state := 0;
    fill_valve := FALSE;
    discharge_valve := FALSE;
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
    TON_Duration : TIME := T#5s;
    TOF_Duration : TIME := T#5s;

    start : BOOL;
    stop : BOOL;
    start_edge : R_TRIG;
    tank_control : FB_FillingTank;
END_VAR

start_edge(CLK := StartCommand);
start := start_edge.Q;
stop := StopCommand;

tank_control(
    start := start,
    stop := stop,
    LSH := LSH,
    LSHH := LSHH,
    TON_Duration := TON_Duration,
    TOF_Duration := TOF_Duration
);

FillValve := tank_control.fill_valve;
DischargeValve := tank_control.discharge_valve;

END_PROGRAM
