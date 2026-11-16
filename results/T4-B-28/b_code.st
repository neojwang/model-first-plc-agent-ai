FUNCTION_BLOCK LevelControl
VAR_INPUT
    StartCommand : BOOL;
    StopCommand : BOOL;
    LevelMeter : INT;
    full_scale_value : INT;
    Kp : REAL := 20.0;
    Ti : REAL := 5.0;
    Td : REAL := 0.0;
END_VAR

VAR_OUTPUT
    FillValve : INT;
    DischargeValve : INT;
    fill_valve : BOOL;
    discharge_valve : BOOL;
END_VAR

VAR CONSTANT
    h_span : REAL := 10.0;
    cycle_seconds : REAL := 0.02;
    t_h : TIME := T#10s;

    (* Numeric region codes avoid the reserved standard function name MID.
       r = 0: LOW; r = 1: MID; r = 2: HIGH. *)
    region_low : INT := 0;
    region_middle : INT := 1;
    region_high : INT := 2;
END_VAR

VAR
    start_edge : R_TRIG;
    hold_timer : TON;

    start : BOOL;
    stop : BOOL;
    settled : BOOL;
    r : INT := 0;

    control_state : INT := 0;
    h : REAL;
    h_target : REAL;
    h_sp : REAL;
    h_max : REAL;
    eps : REAL;
    e : REAL;

    previous_error : REAL := 0.0;
    integral_term : REAL := 0.0;
    proportional_term : REAL;
    derivative_term : REAL;
    integral_increment : REAL;
    candidate_integral : REAL;
    candidate_output : REAL;
    pid_output : REAL;
    output_clamped : BOOL;
END_VAR

start_edge(CLK := StartCommand);
start := start_edge.Q;
stop := StopCommand;

h_target := 0.8 * h_span;
h_sp := h_target;
h_max := 0.9 * h_span;
eps := 0.02 * h_span;

IF full_scale_value > 0 THEN
    h := INT_TO_REAL(LevelMeter) * h_span
         / INT_TO_REAL(full_scale_value);
ELSE
    h := 0.0;
END_IF;

e := h_sp - h;

IF h < h_target THEN
    r := region_low;
ELSIF h < h_max THEN
    r := region_middle;
ELSE
    r := region_high;
END_IF;

FillValve := 0;
DischargeValve := 0;
fill_valve := FALSE;
discharge_valve := FALSE;

IF stop THEN
    control_state := 0;
END_IF;

IF control_state = 0 THEN
    integral_term := 0.0;
    previous_error := e;

    IF start AND NOT stop AND (full_scale_value > 0) THEN
        control_state := 1;
    END_IF;
END_IF;

hold_timer(
    IN := (control_state = 1)
          AND NOT stop
          AND (r <> region_high)
          AND (ABS(e) <= eps),
    PT := t_h
);
settled := hold_timer.Q;

IF control_state = 1 THEN
    IF stop OR settled OR (r = region_high)
       OR (full_scale_value <= 0) THEN
        control_state := 0;
        integral_term := 0.0;
        previous_error := e;
    ELSE
        proportional_term := Kp * e;

        derivative_term := 0.0;
        IF Td > 0.0 THEN
            derivative_term := Kp * Td
                               * (e - previous_error)
                               / cycle_seconds;
        END_IF;

        integral_increment := 0.0;
        IF Ti > 0.0 THEN
            integral_increment := Kp * e * cycle_seconds / Ti;
        END_IF;

        candidate_integral := integral_term + integral_increment;
        candidate_output := proportional_term
                            + candidate_integral
                            + derivative_term;

        (* Suspend integration whenever the candidate output saturates. *)
        output_clamped := (candidate_output < 0.0)
                          OR (candidate_output > 100.0);

        IF NOT output_clamped THEN
            integral_term := candidate_integral;
        END_IF;

        pid_output := proportional_term
                      + integral_term
                      + derivative_term;

        IF pid_output > 100.0 THEN
            pid_output := 100.0;
        ELSIF pid_output < 0.0 THEN
            pid_output := 0.0;
        END_IF;

        previous_error := e;

        fill_valve := TRUE;
        discharge_valve := TRUE;

        FillValve := REAL_TO_INT(
            pid_output * INT_TO_REAL(full_scale_value) / 100.0
        );
        DischargeValve := REAL_TO_INT(
            0.4 * INT_TO_REAL(full_scale_value)
        );
    END_IF;
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
END_VAR

VAR
    controller : LevelControl;
    Kp : REAL := 20.0;
    Ti : REAL := 5.0;
    Td : REAL := 0.0;
END_VAR

controller(
    StartCommand := StartCommand,
    StopCommand := StopCommand,
    LevelMeter := LevelMeter,
    full_scale_value := FULL_SCALE,
    Kp := Kp,
    Ti := Ti,
    Td := Td
);

FillValve := controller.FillValve;
DischargeValve := controller.DischargeValve;

END_PROGRAM


CONFIGURATION Config0
RESOURCE Res0 ON PLC
    TASK ControlTask(INTERVAL := T#20ms, PRIORITY := 0);
    PROGRAM MainInstance WITH ControlTask : Main;
END_RESOURCE
END_CONFIGURATION
