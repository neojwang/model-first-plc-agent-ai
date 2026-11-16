FUNCTION_BLOCK LevelControl
VAR_INPUT
    start       : BOOL;
    stop        : BOOL;
    h           : REAL;
    h_sp        : REAL;
    h_target    : REAL;
    h_max       : REAL;
    eps         : REAL;
    t_h         : TIME;
    Kp          : REAL;
    Ti          : REAL;
    Td          : REAL;
    cycle_s     : REAL;
END_VAR
VAR_OUTPUT
    fill_valve      : BOOL := FALSE;
    discharge_valve : BOOL := FALSE;
    fill_percent    : REAL := 0.0;
    settled         : BOOL := FALSE;
    (* String values avoid using the standard function name MID as an identifier. *)
    r               : STRING[4] := 'LOW';
END_VAR
VAR
    control_state       : INT := 0;
    hold_timer          : TON;
    error_value         : REAL := 0.0;
    previous_error      : REAL := 0.0;
    proportional_term   : REAL := 0.0;
    integral_term       : REAL := 0.0;
    candidate_integral  : REAL := 0.0;
    derivative_term     : REAL := 0.0;
    unconstrained       : REAL := 0.0;
END_VAR

error_value := h_sp - h;

IF h < h_target THEN
    r := 'LOW';
ELSIF h < h_max THEN
    r := 'MID';
ELSE
    r := 'HIGH';
END_IF;

IF stop THEN
    control_state := 0;
END_IF;

(* Evaluate before accepting a new start so each run resets the timer. *)
hold_timer(
    IN := (control_state = 1) AND NOT stop
          AND (ABS(error_value) <= eps),
    PT := t_h
);
settled := hold_timer.Q;

IF NOT stop THEN
    CASE control_state OF
        0:
            IF start THEN
                integral_term := 0.0;
                previous_error := error_value;
                control_state := 1;
            END_IF;
        1:
            IF settled OR (r = 'HIGH') THEN
                control_state := 0;
            END_IF;
    ELSE
        control_state := 0;
    END_CASE;
END_IF;

(* An overfill condition also prevents starting regulation. *)
IF (control_state = 1) AND (r = 'HIGH') THEN
    control_state := 0;
END_IF;

fill_valve := FALSE;
discharge_valve := FALSE;
fill_percent := 0.0;

CASE control_state OF
    0:
        integral_term := 0.0;
        previous_error := error_value;

    1:
        proportional_term := Kp * error_value;

        derivative_term := 0.0;
        IF (Td > 0.0) AND (cycle_s > 0.0) THEN
            derivative_term :=
                Kp * Td * (error_value - previous_error) / cycle_s;
        END_IF;

        candidate_integral := integral_term;
        IF (Ti > 0.0) AND (cycle_s > 0.0) THEN
            candidate_integral :=
                integral_term + Kp * error_value * cycle_s / Ti;
        END_IF;

        unconstrained :=
            proportional_term + candidate_integral + derivative_term;

        (* Conditional integration: never commit an integral update
           on a scan whose requested valve opening is clamped. *)
        IF unconstrained > 100.0 THEN
            fill_percent := 100.0;
        ELSIF unconstrained < 0.0 THEN
            fill_percent := 0.0;
        ELSE
            integral_term := candidate_integral;
            fill_percent := unconstrained;
        END_IF;

        previous_error := error_value;
        fill_valve := TRUE;
        discharge_valve := TRUE;

ELSE
    control_state := 0;
END_CASE;

END_FUNCTION_BLOCK


PROGRAM Main
VAR
    StartCommand   AT %IX100.0 : BOOL;
    StopCommand    AT %IX100.1 : BOOL;
    LevelMeter     AT %IW100   : INT;
    FillValve      AT %QW100   : INT;
    DischargeValve AT %QW101   : INT;
END_VAR
VAR CONSTANT
    FULL_SCALE : INT := 1000;
    h_span     : REAL := 10.0;
    t_h        : TIME := T#10s;
    cycle_s    : REAL := 0.02;
END_VAR
VAR
    start_edge : R_TRIG;
    controller : LevelControl;

    start      : BOOL := FALSE;
    stop       : BOOL := FALSE;
    h          : REAL := 0.0;
    h_sp       : REAL := 8.0;
    h_target   : REAL := 8.0;
    h_max      : REAL := 9.0;
    eps        : REAL := 0.2;

    (* Example commissioning gains: output is percent, level is volts.
       Ti and Td are expressed in seconds; Ti <= 0 disables integration. *)
    Kp         : REAL := 20.0;
    Ti         : REAL := 5.0;
    Td         : REAL := 0.0;
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
    h_sp := h_sp,
    h_target := h_target,
    h_max := h_max,
    eps := eps,
    t_h := t_h,
    Kp := Kp,
    Ti := Ti,
    Td := Td,
    cycle_s := cycle_s
);

FillValve := 0;
DischargeValve := 0;

IF controller.fill_valve AND NOT stop THEN
    FillValve := REAL_TO_INT(
        controller.fill_percent * INT_TO_REAL(FULL_SCALE) / 100.0
    );
END_IF;

IF controller.discharge_valve AND NOT stop THEN
    DischargeValve := REAL_TO_INT(0.4 * INT_TO_REAL(FULL_SCALE));
END_IF;

END_PROGRAM


CONFIGURATION Config0
    RESOURCE Res0 ON PLC
        TASK ControlTask(INTERVAL := T#20ms, PRIORITY := 0);
        PROGRAM MainInstance WITH ControlTask : Main;
    END_RESOURCE
END_CONFIGURATION
