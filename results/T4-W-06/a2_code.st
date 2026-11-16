FUNCTION_BLOCK FB_LevelControl
VAR_INPUT
    StartCommand : BOOL;
    StopCommand : BOOL;
    LevelMeter : INT;
    Kp : REAL := 1.0;
    Ti : REAL := 5.0;
    Td : REAL := 0.0;
    cycle_s : REAL := 0.02;
    h_span : REAL := 10.0;
    h_target : REAL := 8.0;
    h_max : REAL := 9.0;
    eps : REAL := 0.2;
    t_h : TIME := T#10s;
END_VAR
VAR_OUTPUT
    FillValve : INT;
    DischargeValve : INT;
    fill_valve : BOOL;
    discharge_valve : BOOL;
END_VAR
VAR CONSTANT
    FULL_SCALE : INT := 1000;
END_VAR
VAR
    start_edge : R_TRIG;
    hold_timer : TON;
    start : BOOL;
    stop : BOOL;
    settled : BOOL;

    (* Level-region encoding: 0 = LOW, 1 = MID, 2 = HIGH. *)
    r : INT := 0;
    sequence_state : INT := 0;
    x0 : BOOL := TRUE;
    x1 : BOOL := FALSE;

    h : REAL;
    e : REAL;
    normalized_error : REAL;
    previous_error : REAL := 0.0;
    first_pid_scan : BOOL := TRUE;

    proportional_term : REAL;
    integral_term : REAL := 0.0;
    trial_integral : REAL;
    derivative_term : REAL;
    raw_demand : REAL;
    bounded_demand : REAL := 0.0;
END_VAR

start_edge(CLK := StartCommand);
start := start_edge.Q;
stop := StopCommand;

h := INT_TO_REAL(LevelMeter) * h_span / INT_TO_REAL(FULL_SCALE);
e := h_target - h;

IF h < h_target THEN
    r := 0;
ELSIF h < h_max THEN
    r := 1;
ELSE
    r := 2;
END_IF;

(* Settling requires an uninterrupted in-band interval during regulation. *)
hold_timer(
    IN := (sequence_state = 1) AND NOT stop AND (ABS(e) <= eps),
    PT := t_h
);
settled := hold_timer.Q;

IF stop THEN
    sequence_state := 0;
ELSE
    CASE sequence_state OF
        0:
            IF start AND (r <> 2) THEN
                sequence_state := 1;
            END_IF;

        1:
            IF settled OR (r = 2) THEN
                sequence_state := 0;
            END_IF;

    ELSE
        sequence_state := 0;
    END_CASE;
END_IF;

x0 := sequence_state = 0;
x1 := sequence_state = 1;
fill_valve := x1;
discharge_valve := x1;

(* Defaults also enforce zero outputs on stop and in the initial step. *)
FillValve := 0;
DischargeValve := 0;

IF x1 THEN
    (* PID gains act on error normalized to the measuring span.
       Ti, Td and cycle_s are expressed in seconds. *)
    IF h_span > 0.0 THEN
        normalized_error := e / h_span;
    ELSE
        normalized_error := 0.0;
    END_IF;

    proportional_term := Kp * normalized_error;

    derivative_term := 0.0;
    IF NOT first_pid_scan AND (cycle_s > 0.0) AND (Td > 0.0) THEN
        derivative_term :=
            Kp * Td * (normalized_error - previous_error) / cycle_s;
    END_IF;

    trial_integral := integral_term;
    IF (Ti > 0.0) AND (cycle_s > 0.0) THEN
        trial_integral :=
            integral_term + Kp * normalized_error * cycle_s / Ti;
    END_IF;

    raw_demand := proportional_term + trial_integral + derivative_term;

    (* Clamp the demand to 0..1. Do not commit an integral update
       in a scan whose candidate output is clamped. *)
    IF raw_demand > 1.0 THEN
        bounded_demand := 1.0;
    ELSIF raw_demand < 0.0 THEN
        bounded_demand := 0.0;
    ELSE
        bounded_demand := raw_demand;
        integral_term := trial_integral;
    END_IF;

    previous_error := normalized_error;
    first_pid_scan := FALSE;

    FillValve := REAL_TO_INT(bounded_demand * INT_TO_REAL(FULL_SCALE));
    DischargeValve := REAL_TO_INT(0.4 * INT_TO_REAL(FULL_SCALE));
ELSE
    (* Reset regulation-owned memory before the next run. *)
    hold_timer(IN := FALSE, PT := t_h);
    settled := FALSE;
    integral_term := 0.0;
    previous_error := 0.0;
    first_pid_scan := TRUE;
    bounded_demand := 0.0;
END_IF;

END_FUNCTION_BLOCK


PROGRAM Main
VAR
    StartCommand AT %IX100.0 : BOOL;
    StopCommand AT %IX100.1 : BOOL;
    LevelMeter AT %IW100 : INT;
    FillValve AT %QW100 : INT;
    DischargeValve AT %QW101 : INT;
END_VAR
VAR
    level_controller : FB_LevelControl;

    (* Commissioning values: tune these gains for the actual scene. *)
    Kp : REAL := 1.0;
    Ti : REAL := 5.0;
    Td : REAL := 0.0;

    fill_valve : BOOL;
    discharge_valve : BOOL;
END_VAR

level_controller(
    StartCommand := StartCommand,
    StopCommand := StopCommand,
    LevelMeter := LevelMeter,
    Kp := Kp,
    Ti := Ti,
    Td := Td,
    cycle_s := 0.02,
    h_span := 10.0,
    h_target := 8.0,
    h_max := 9.0,
    eps := 0.2,
    t_h := T#10s
);

FillValve := level_controller.FillValve;
DischargeValve := level_controller.DischargeValve;
fill_valve := level_controller.fill_valve;
discharge_valve := level_controller.discharge_valve;

END_PROGRAM


CONFIGURATION Config0
    RESOURCE Res0 ON PLC
        TASK ControlTask(INTERVAL := T#20ms, PRIORITY := 0);
        PROGRAM MainInstance WITH ControlTask : Main;
    END_RESOURCE
END_CONFIGURATION
