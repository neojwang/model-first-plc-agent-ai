FUNCTION_BLOCK FB_LevelControl
VAR_INPUT
    StartCommand : BOOL;
    StopCommand : BOOL;
    LevelMeter : INT;
    h_span : REAL := 10.0;
    t_h : TIME := T#10s;
    Kp : REAL := 20.0;
    Ti : REAL := 5.0;
    Td : REAL := 0.0;
    cycle_seconds : REAL := 0.02;
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
    r : INT;

    state_code : INT := 0;
    pid_active_previous : BOOL := FALSE;

    h : REAL;
    h_sp : REAL;
    h_target : REAL;
    h_max : REAL;
    eps : REAL;
    error_value : REAL;
    previous_error : REAL := 0.0;

    proportional_term : REAL;
    integral_term : REAL := 0.0;
    integral_candidate : REAL;
    derivative_term : REAL;
    raw_demand : REAL;
    candidate_demand : REAL;
    bounded_demand : REAL;
END_VAR

(* Rising-edge detection is executed even while stopped. *)
start_edge(CLK := StartCommand);
start := start_edge.Q;
stop := StopCommand;

h := INT_TO_REAL(LevelMeter) * h_span / INT_TO_REAL(FULL_SCALE);
h_sp := 0.8 * h_span;
h_target := h_sp;
h_max := 0.9 * h_span;
eps := 0.02 * h_span;
error_value := h_sp - h;

(* Region encoding: 0 = LOW, 1 = MID, 2 = HIGH. *)
IF h < h_target THEN
    r := 0;
ELSIF h < h_max THEN
    r := 1;
ELSE
    r := 2;
END_IF;

(* Stop has priority over all normal transitions. *)
IF stop THEN
    state_code := 0;
END_IF;

(* The hold condition must remain true continuously during regulation. *)
hold_timer(
    IN := (state_code = 1) AND (ABS(error_value) <= eps),
    PT := t_h
);
settled := hold_timer.Q;

CASE state_code OF
    0:
        IF start AND NOT stop AND (r <> 2) THEN
            state_code := 1;
        END_IF;

    1:
        IF stop OR settled OR (r = 2) THEN
            state_code := 0;
        END_IF;

ELSE
    state_code := 0;
END_CASE;

fill_valve := (state_code = 1);
discharge_valve := (state_code = 1);

FillValve := 0;
DischargeValve := 0;

IF fill_valve THEN
    (* PID demand is expressed as percent valve opening.
       Kp has units percent per level unit; Ti and Td are in seconds.
       Ti <= 0 disables the integral term. *)
    IF NOT pid_active_previous THEN
        previous_error := error_value;
        integral_term := 0.0;
    END_IF;

    proportional_term := Kp * error_value;

    derivative_term := 0.0;
    IF (Td > 0.0) AND (cycle_seconds > 0.0) THEN
        derivative_term :=
            Kp * Td * (error_value - previous_error) / cycle_seconds;
    END_IF;

    IF Ti <= 0.0 THEN
        integral_term := 0.0;
    END_IF;

    raw_demand := proportional_term + integral_term + derivative_term;

    (* Suspend integration whenever demand is saturated.
       Also reject an integral update that would cause saturation. *)
    IF (Ti > 0.0) AND (cycle_seconds > 0.0)
       AND (raw_demand >= 0.0) AND (raw_demand <= 100.0) THEN

        integral_candidate :=
            integral_term + Kp * error_value * cycle_seconds / Ti;
        candidate_demand :=
            proportional_term + integral_candidate + derivative_term;

        IF (candidate_demand >= 0.0) AND (candidate_demand <= 100.0) THEN
            integral_term := integral_candidate;
            raw_demand := candidate_demand;
        END_IF;
    END_IF;

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

    previous_error := error_value;
ELSE
    integral_term := 0.0;
    previous_error := error_value;
    bounded_demand := 0.0;
END_IF;

IF discharge_valve THEN
    DischargeValve := REAL_TO_INT(0.4 * INT_TO_REAL(FULL_SCALE));
END_IF;

pid_active_previous := fill_valve;

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
    level_control : FB_LevelControl;
    h_span : REAL := 10.0;
    t_h : TIME := T#10s;

    (* Initial tuning values; adjust for the simulated plant. *)
    Kp : REAL := 20.0;
    Ti : REAL := 5.0;
    Td : REAL := 0.0;
END_VAR

level_control(
    StartCommand := StartCommand,
    StopCommand := StopCommand,
    LevelMeter := LevelMeter,
    h_span := h_span,
    t_h := t_h,
    Kp := Kp,
    Ti := Ti,
    Td := Td,
    cycle_seconds := 0.02
);

FillValve := level_control.FillValve;
DischargeValve := level_control.DischargeValve;

END_PROGRAM


CONFIGURATION Config0
    RESOURCE Res0 ON PLC
        TASK ControlTask(INTERVAL := T#20ms, PRIORITY := 0);
        PROGRAM MainInstance WITH ControlTask : Main;
    END_RESOURCE
END_CONFIGURATION
