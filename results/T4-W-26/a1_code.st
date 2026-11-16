FUNCTION_BLOCK LevelControlRuntime
VAR_INPUT
    start : BOOL;
    stop : BOOL;
    h : REAL;
    h_span : REAL;
    h_sp : REAL;
    h_target : REAL;
    h_max : REAL;
    eps : REAL;
    t_h : TIME;
    Kp : REAL;
    Ti : REAL;
    Td : REAL;
    cycle_seconds : REAL;
    full_scale_value : INT;
END_VAR
VAR_OUTPUT
    fill_valve : BOOL;
    discharge_valve : BOOL;
    fill_command : INT;
    discharge_command : INT;
END_VAR
VAR
    x0 : BOOL := TRUE;
    x1 : BOOL := FALSE;
    settled : BOOL := FALSE;
    r : INT := 0;
    settle_timer : TON;
    level_error : REAL;
    normalized_error : REAL;
    previous_error : REAL := 0.0;
    integral_term : REAL := 0.0;
    derivative_term : REAL := 0.0;
    unconstrained_demand : REAL := 0.0;
    bounded_demand : REAL := 0.0;
    pid_initialized : BOOL := FALSE;
END_VAR

(* Region encoding: 0 = LOW, 1 = MID, 2 = HIGH. *)
IF h < h_target THEN
    r := 0;
ELSIF h < h_max THEN
    r := 1;
ELSE
    r := 2;
END_IF;

level_error := h_sp - h;

(* Settling requires an uninterrupted tolerance interval while x1 is active. *)
settle_timer(
    IN := x1 AND (ABS(level_error) <= eps),
    PT := t_h
);
settled := settle_timer.Q;

(* Evaluate transitions from the situation at the start of this invocation. *)
IF x0 THEN
    IF start AND NOT stop AND (r <> 2) THEN
        x0 := FALSE;
        x1 := TRUE;
    END_IF;
ELSIF x1 THEN
    IF stop OR settled OR (r = 2) THEN
        x1 := FALSE;
        x0 := TRUE;
    END_IF;
END_IF;

fill_valve := x1;
discharge_valve := x1;

IF fill_valve THEN
    (* PID uses normalized level error and a demand range of 0.0 to 1.0. *)
    normalized_error := level_error / h_span;

    IF NOT pid_initialized THEN
        previous_error := normalized_error;
        integral_term := 0.0;
        pid_initialized := TRUE;
    END_IF;

    derivative_term := 0.0;
    IF (Td > 0.0) AND (cycle_seconds > 0.0) THEN
        derivative_term :=
            Kp * Td * (normalized_error - previous_error) / cycle_seconds;
    END_IF;

    unconstrained_demand :=
        Kp * normalized_error + integral_term + derivative_term;

    IF unconstrained_demand <= 0.0 THEN
        bounded_demand := 0.0;
    ELSIF unconstrained_demand >= 1.0 THEN
        bounded_demand := 1.0;
    ELSE
        bounded_demand := unconstrained_demand;

        (* Accumulate only while the current output is not clamped.
           This update contributes to the next invocation's PID output. *)
        IF (Ti > 0.0) AND (cycle_seconds > 0.0) THEN
            integral_term := integral_term
                + Kp * normalized_error * cycle_seconds / Ti;
        END_IF;
    END_IF;

    previous_error := normalized_error;
    fill_command :=
        REAL_TO_INT(bounded_demand * INT_TO_REAL(full_scale_value));
ELSE
    fill_command := 0;
    bounded_demand := 0.0;
    integral_term := 0.0;
    derivative_term := 0.0;
    previous_error := 0.0;
    pid_initialized := FALSE;
END_IF;

IF discharge_valve THEN
    discharge_command := REAL_TO_INT(0.4 * INT_TO_REAL(full_scale_value));
ELSE
    discharge_command := 0;
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
VAR CONSTANT
    FULL_SCALE : INT := 1000;
    cycle_seconds : REAL := 0.02;
END_VAR
VAR
    start_edge : R_TRIG;
    controller : LevelControlRuntime;

    start : BOOL;
    stop : BOOL;
    h : REAL;
    h_span : REAL := 10.0;
    h_sp : REAL;
    h_target : REAL;
    h_max : REAL;
    eps : REAL;
    t_h : TIME := T#10s;

    (* Initial tuning values; adjust for the plant.
       Kp uses normalized error; Ti and Td are in seconds.
       Ti <= 0 disables integration; Td <= 0 disables differentiation. *)
    Kp : REAL := 1.0;
    Ti : REAL := 10.0;
    Td : REAL := 0.0;
END_VAR

start_edge(CLK := StartCommand);
start := start_edge.Q;
stop := StopCommand;

h := INT_TO_REAL(LevelMeter) * h_span / INT_TO_REAL(FULL_SCALE);
h_sp := 0.8 * h_span;
h_target := h_sp;
h_max := 0.9 * h_span;
eps := 0.02 * h_span;

controller(
    start := start,
    stop := stop,
    h := h,
    h_span := h_span,
    h_sp := h_sp,
    h_target := h_target,
    h_max := h_max,
    eps := eps,
    t_h := t_h,
    Kp := Kp,
    Ti := Ti,
    Td := Td,
    cycle_seconds := cycle_seconds,
    full_scale_value := FULL_SCALE
);

FillValve := controller.fill_command;
DischargeValve := controller.discharge_command;

END_PROGRAM


CONFIGURATION Config0
    RESOURCE Res0 ON PLC
        TASK MainTask(INTERVAL := T#20ms, PRIORITY := 0);
        PROGRAM MainInstance WITH MainTask : Main;
    END_RESOURCE
END_CONFIGURATION
