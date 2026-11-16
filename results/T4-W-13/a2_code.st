FUNCTION_BLOCK FB_LevelControl
VAR_INPUT
    StartCommand : BOOL;
    StopCommand : BOOL;
    LevelMeter : INT;
    h_span : REAL;
    h_sp : REAL;
    h_target : REAL;
    h_max : REAL;
    eps : REAL;
    t_h : TIME;
    Kp : REAL;
    Ti : REAL;
    Td : REAL;
END_VAR
VAR_OUTPUT
    FillValve : INT;
    DischargeValve : INT;
    fill_valve : BOOL;
    discharge_valve : BOOL;
END_VAR
VAR CONSTANT
    FULL_SCALE : INT := 1000;
    scan_seconds : REAL := 0.02;
END_VAR
VAR
    start_edge : R_TRIG;
    hold_timer : TON;
    start : BOOL;
    stop : BOOL;
    settled : BOOL;
    r : INT;
    sequence_state : INT := 0;
    x0 : BOOL := TRUE;
    x1 : BOOL := FALSE;

    h : REAL;
    e : REAL;
    previous_error : REAL := 0.0;
    pid_was_active : BOOL := FALSE;
    proportional_term : REAL;
    integral_term : REAL := 0.0;
    derivative_term : REAL;
    integral_candidate : REAL;
    demand_candidate : REAL;
    raw_demand : REAL;
    bounded_demand : REAL;
END_VAR

(* r encoding: 0 = LOW, 1 = MID, 2 = HIGH. *)
start_edge(CLK := StartCommand);
start := start_edge.Q;
stop := StopCommand;

h := INT_TO_REAL(LevelMeter) * h_span / INT_TO_REAL(FULL_SCALE);
e := h_sp - h;

IF h >= h_max THEN
    r := 2;
ELSIF h >= h_target THEN
    r := 1;
ELSE
    r := 0;
END_IF;

(* The settling interval must be continuous and belong to regulation. *)
hold_timer(
    IN := (sequence_state = 1) AND NOT stop
          AND (r <> 2) AND (ABS(e) <= eps),
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

FillValve := 0;
DischargeValve := 0;

IF fill_valve THEN
    proportional_term := Kp * e;

    (* Suppress a derivative kick on entry into regulation. *)
    IF pid_was_active THEN
        derivative_term :=
            Kp * Td * (e - previous_error) / scan_seconds;
    ELSE
        derivative_term := 0.0;
    END_IF;

    raw_demand := proportional_term + integral_term + derivative_term;

    (* Freeze integration whenever the demand is clamped.
       Also reject an integral update that would cause clamping. *)
    IF (Ti > 0.0)
       AND (raw_demand >= 0.0)
       AND (raw_demand <= 100.0) THEN

        integral_candidate :=
            integral_term + Kp * e * scan_seconds / Ti;

        demand_candidate :=
            proportional_term + integral_candidate + derivative_term;

        IF (demand_candidate >= 0.0)
           AND (demand_candidate <= 100.0) THEN
            integral_term := integral_candidate;
        END_IF;
    END_IF;

    raw_demand := proportional_term + integral_term + derivative_term;

    IF raw_demand > 100.0 THEN
        bounded_demand := 100.0;
    ELSIF raw_demand < 0.0 THEN
        bounded_demand := 0.0;
    ELSE
        bounded_demand := raw_demand;
    END_IF;

    FillValve := REAL_TO_INT(
        bounded_demand * INT_TO_REAL(FULL_SCALE) / 100.0
    );

    previous_error := e;
    pid_was_active := TRUE;
ELSE
    (* Chosen restart policy: reset PID memory while idle. *)
    integral_term := 0.0;
    derivative_term := 0.0;
    bounded_demand := 0.0;
    previous_error := e;
    pid_was_active := FALSE;
END_IF;

IF discharge_valve THEN
    DischargeValve := REAL_TO_INT(0.4 * INT_TO_REAL(FULL_SCALE));
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
    controller : FB_LevelControl;
    h_span : REAL := 10.0;
    t_h : TIME := T#10s;

    (* Initial tuning values; adjust for the plant.
       Kp is percent opening per level unit; Ti and Td are seconds. *)
    Kp : REAL := 10.0;
    Ti : REAL := 5.0;
    Td : REAL := 0.0;

    fill_valve : BOOL;
    discharge_valve : BOOL;
END_VAR

controller(
    StartCommand := StartCommand,
    StopCommand := StopCommand,
    LevelMeter := LevelMeter,
    h_span := h_span,
    h_sp := 0.8 * h_span,
    h_target := 0.8 * h_span,
    h_max := 0.9 * h_span,
    eps := 0.02 * h_span,
    t_h := t_h,
    Kp := Kp,
    Ti := Ti,
    Td := Td,
    FillValve => FillValve,
    DischargeValve => DischargeValve,
    fill_valve => fill_valve,
    discharge_valve => discharge_valve
);

END_PROGRAM


CONFIGURATION Config0
    RESOURCE Res0 ON PLC
        TASK ControlTask(INTERVAL := T#20ms, PRIORITY := 0);
        PROGRAM MainInstance WITH ControlTask : Main;
    END_RESOURCE
END_CONFIGURATION
