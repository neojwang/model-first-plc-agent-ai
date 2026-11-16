FUNCTION_BLOCK LevelControlRuntime
VAR_INPUT
    start : BOOL;
    stop : BOOL;
    h : REAL;
    h_sp : REAL;
    h_target : REAL;
    h_max : REAL;
    eps : REAL;
    h_span : REAL;
    t_h : TIME;
    Kp : REAL;
    Ti : REAL;
    Td : REAL;
    cycle_seconds : REAL;
    full_scale_value : INT;
END_VAR
VAR_OUTPUT
    fill_valve : BOOL := FALSE;
    discharge_valve : BOOL := FALSE;
    fill_command : INT := 0;
    discharge_command : INT := 0;
END_VAR
VAR CONSTANT
    REGION_LOW : INT := 0;
    REGION_MIDDLE : INT := 1;
    REGION_HIGH : INT := 2;
END_VAR
VAR
    x0 : BOOL := TRUE;
    x1 : BOOL := FALSE;
    t1 : BOOL;
    t2 : BOOL;
    r : INT;
    settled : BOOL := FALSE;
    settling_timer : TON;
    level_error : REAL;
    error_percent : REAL;
    previous_error : REAL := 0.0;
    integral_state : REAL := 0.0;
    integral_candidate : REAL;
    proportional_term : REAL;
    derivative_term : REAL;
    raw_demand : REAL;
    bounded_demand : REAL := 0.0;
    pid_initialized : BOOL := FALSE;
END_VAR

level_error := h_sp - h;

IF h < h_target THEN
    r := REGION_LOW;
ELSIF h < h_max THEN
    r := REGION_MIDDLE;
ELSE
    r := REGION_HIGH;
END_IF;

(* Only continuous time within the tolerance band in x1 counts. *)
settling_timer(
    IN := x1 AND NOT stop AND (ABS(level_error) <= eps),
    PT := t_h
);
settled := settling_timer.Q;

(* Evaluate both transitions against the current situation. *)
t1 := x0 AND start AND NOT stop AND NOT (r = REGION_HIGH);
t2 := x1 AND (stop OR settled OR (r = REGION_HIGH));

IF t2 THEN
    x0 := TRUE;
    x1 := FALSE;
ELSIF t1 THEN
    x0 := FALSE;
    x1 := TRUE;
END_IF;

fill_valve := x1;
discharge_valve := x1;

IF x1 THEN
    (* Normalized error gives PID demand in percent opening. *)
    IF h_span > 0.0 THEN
        error_percent := 100.0 * level_error / h_span;
    ELSE
        error_percent := 0.0;
    END_IF;

    IF NOT pid_initialized THEN
        integral_state := 0.0;
        previous_error := error_percent;
        pid_initialized := TRUE;
    END_IF;

    proportional_term := Kp * error_percent;
    derivative_term := 0.0;

    IF cycle_seconds > 0.0 THEN
        derivative_term :=
            Kp * Td * (error_percent - previous_error) / cycle_seconds;
    END_IF;

    (*
       Explicit PID arithmetic permits exact integral suspension.
       Commit the proposed integral only if the proposed demand
       is not clamped. Ti <= 0 disables the integral term.
    *)
    IF Ti > 0.0 THEN
        integral_candidate := integral_state;
        IF cycle_seconds > 0.0 THEN
            integral_candidate :=
                integral_state
                + Kp * error_percent * cycle_seconds / Ti;
        END_IF;
    ELSE
        integral_state := 0.0;
        integral_candidate := 0.0;
    END_IF;

    raw_demand :=
        proportional_term + integral_candidate + derivative_term;

    IF raw_demand > 100.0 THEN
        bounded_demand := 100.0;
    ELSIF raw_demand < 0.0 THEN
        bounded_demand := 0.0;
    ELSE
        bounded_demand := raw_demand;
        integral_state := integral_candidate;
    END_IF;

    previous_error := error_percent;

    fill_command :=
        REAL_TO_INT(
            bounded_demand * INT_TO_REAL(full_scale_value) / 100.0
        );
    discharge_command :=
        REAL_TO_INT(0.4 * INT_TO_REAL(full_scale_value));
ELSE
    fill_command := 0;
    discharge_command := 0;

    integral_state := 0.0;
    integral_candidate := 0.0;
    previous_error := 0.0;
    bounded_demand := 0.0;
    pid_initialized := FALSE;

    (* Reset ownership immediately when x1 becomes inactive. *)
    settling_timer(IN := FALSE, PT := t_h);
    settled := FALSE;
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
    CYCLE_SECONDS : REAL := 0.02;
END_VAR
VAR
    start_edge : R_TRIG;
    controller : LevelControlRuntime;

    start : BOOL := FALSE;
    stop : BOOL := FALSE;
    h : REAL := 0.0;

    h_span : REAL := 10.0;
    h_sp : REAL := 8.0;
    h_target : REAL := 8.0;
    h_max : REAL := 9.0;
    eps : REAL := 0.2;
    t_h : TIME := T#10s;

    (* Initial tuning values; commission these for the simulated plant.
       Kp uses normalized percent error; Ti and Td are in seconds. *)
    Kp : REAL := 1.0;
    Ti : REAL := 10.0;
    Td : REAL := 0.0;
END_VAR

start_edge(CLK := StartCommand);
start := start_edge.Q;
stop := StopCommand;

h := INT_TO_REAL(LevelMeter) * h_span / INT_TO_REAL(FULL_SCALE);

controller(
    start := start,
    stop := stop,
    h := h,
    h_sp := h_sp,
    h_target := h_target,
    h_max := h_max,
    eps := eps,
    h_span := h_span,
    t_h := t_h,
    Kp := Kp,
    Ti := Ti,
    Td := Td,
    cycle_seconds := CYCLE_SECONDS,
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
