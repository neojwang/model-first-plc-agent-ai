FUNCTION_BLOCK LevelControl
VAR_INPUT
    start : BOOL;
    stop : BOOL;
    h : REAL;
    h_target : REAL;
    h_max : REAL;
    eps : REAL;
    t_h : TIME;
    Kp : REAL;
    Ti : REAL;
    Td : REAL;
    sample_seconds : REAL;
END_VAR
VAR_OUTPUT
    fill_valve : BOOL := FALSE;
    discharge_valve : BOOL := FALSE;
    valve_demand : REAL := 0.0;
END_VAR
VAR CONSTANT
    REGION_LOW : INT := 0;
    REGION_MIDDLE : INT := 1; (* MID region; MID is a reserved standard name. *)
    REGION_HIGH : INT := 2;
END_VAR
VAR
    state_index : INT := 0;
    r : INT := 0;
    settled : BOOL := FALSE;
    hold_timer : TON;
    error_value : REAL := 0.0;
    previous_error : REAL := 0.0;
    proportional_term : REAL := 0.0;
    integral_term : REAL := 0.0;
    candidate_integral : REAL := 0.0;
    derivative_term : REAL := 0.0;
    candidate_output : REAL := 0.0;
    raw_output : REAL := 0.0;
END_VAR

error_value := h_target - h;

IF h < h_target THEN
    r := REGION_LOW;
ELSIF h < h_max THEN
    r := REGION_MIDDLE;
ELSE
    r := REGION_HIGH;
END_IF;

hold_timer(
    IN := (state_index = 1)
          AND NOT stop
          AND (r <> REGION_HIGH)
          AND (ABS(error_value) <= eps),
    PT := t_h
);
settled := hold_timer.Q;

IF stop THEN
    state_index := 0;
ELSE
    CASE state_index OF
        0:
            IF start AND (r <> REGION_HIGH) THEN
                integral_term := 0.0;
                previous_error := error_value;
                state_index := 1;
            END_IF;

        1:
            IF settled OR (r = REGION_HIGH) THEN
                state_index := 0;
            END_IF;

    ELSE
        state_index := 0;
    END_CASE;
END_IF;

fill_valve := FALSE;
discharge_valve := FALSE;
valve_demand := 0.0;

IF state_index = 1 THEN
    fill_valve := TRUE;
    discharge_valve := TRUE;

    proportional_term := Kp * error_value;

    derivative_term := 0.0;
    IF (Td > 0.0) AND (sample_seconds > 0.0) THEN
        derivative_term :=
            Kp * Td * (error_value - previous_error) / sample_seconds;
    END_IF;

    candidate_integral := integral_term;
    IF (Ti > 0.0) AND (sample_seconds > 0.0) THEN
        candidate_integral :=
            integral_term + Kp * error_value * sample_seconds / Ti;
    ELSE
        candidate_integral := 0.0;
        integral_term := 0.0;
    END_IF;

    candidate_output :=
        proportional_term + candidate_integral + derivative_term;

    (* Freeze integration whenever the candidate output is saturated. *)
    IF (candidate_output >= 0.0) AND (candidate_output <= 1.0) THEN
        integral_term := candidate_integral;
    END_IF;

    raw_output := proportional_term + integral_term + derivative_term;

    IF raw_output < 0.0 THEN
        valve_demand := 0.0;
    ELSIF raw_output > 1.0 THEN
        valve_demand := 1.0;
    ELSE
        valve_demand := raw_output;
    END_IF;

    previous_error := error_value;
ELSE
    integral_term := 0.0;
    previous_error := error_value;
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
    h_span : REAL := 10.0;
    sample_seconds : REAL := 0.02;
END_VAR
VAR
    start_edge : R_TRIG;
    controller : LevelControl;

    start : BOOL := FALSE;
    stop : BOOL := FALSE;
    h : REAL := 0.0;
    h_sp : REAL := 8.0;
    h_target : REAL := 8.0;
    h_max : REAL := 9.0;
    eps : REAL := 0.2;
    t_h : TIME := T#10s;

    (* PID output is normalized to 0..1; level is measured in volts.
       Ti and Td are expressed in seconds. Tune these gains for the plant. *)
    Kp : REAL := 0.2;
    Ti : REAL := 5.0;
    Td : REAL := 0.0;

    fill_valve : BOOL := FALSE;
    discharge_valve : BOOL := FALSE;
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
    h_target := h_target,
    h_max := h_max,
    eps := eps,
    t_h := t_h,
    Kp := Kp,
    Ti := Ti,
    Td := Td,
    sample_seconds := sample_seconds
);

fill_valve := controller.fill_valve;
discharge_valve := controller.discharge_valve;

FillValve := 0;
DischargeValve := 0;

IF fill_valve AND NOT stop THEN
    FillValve :=
        REAL_TO_INT(controller.valve_demand * INT_TO_REAL(FULL_SCALE));
END_IF;

IF discharge_valve AND NOT stop THEN
    DischargeValve := REAL_TO_INT(0.4 * INT_TO_REAL(FULL_SCALE));
END_IF;

END_PROGRAM


CONFIGURATION Config0
    RESOURCE Res0 ON PLC
        TASK ControlTask(INTERVAL := T#20ms, PRIORITY := 0);
        PROGRAM MainInstance WITH ControlTask : Main;
    END_RESOURCE
END_CONFIGURATION
