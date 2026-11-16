FUNCTION_BLOCK LevelControl
VAR_INPUT
    StartCommand : BOOL;
    StopCommand : BOOL;
    LevelMeter : INT;
    FULL_SCALE : INT;
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

    start : BOOL;
    stop : BOOL;
    settled : BOOL;
    r : INT;
    fill_valve : BOOL;
    discharge_valve : BOOL;
END_VAR
VAR CONSTANT
    LOW : INT := 0;
    HIGH : INT := 2;
    (* Region value 1 means MID; MID is a reserved standard function name. *)
    cycle_seconds : REAL := 0.02;
END_VAR
VAR
    start_edge : R_TRIG;
    hold_timer : TON;

    state_number : INT := 0;
    h : REAL;
    error_level : REAL;
    error_normalized : REAL;
    previous_error : REAL := 0.0;

    integral_term : REAL := 0.0;
    proportional_term : REAL := 0.0;
    derivative_term : REAL := 0.0;
    integral_candidate : REAL;
    output_candidate : REAL;
    controller_output : REAL := 0.0;
END_VAR

start_edge(CLK := StartCommand);
start := start_edge.Q;
stop := StopCommand;

h := INT_TO_REAL(LevelMeter) * h_span / INT_TO_REAL(FULL_SCALE);
error_level := h_sp - h;
error_normalized := error_level / h_span;

IF h < h_target THEN
    r := LOW;
ELSIF h < h_max THEN
    r := 1; (* MID *)
ELSE
    r := HIGH;
END_IF;

(* Stop takes precedence over a simultaneous start event. *)
IF stop THEN
    state_number := 0;
ELSIF (state_number = 0) AND start THEN
    state_number := 10;
    integral_term := 0.0;
    previous_error := error_normalized;
END_IF;

hold_timer(
    IN := (state_number = 10)
          AND NOT stop
          AND (r <> HIGH)
          AND (ABS(error_level) <= eps),
    PT := t_h
);
settled := hold_timer.Q;

IF (state_number = 10) AND (settled OR (r = HIGH)) THEN
    state_number := 0;
END_IF;

(* Safe defaults apply in the initial step and on every stop. *)
FillValve := 0;
DischargeValve := 0;
fill_valve := FALSE;
discharge_valve := FALSE;

CASE state_number OF
    0:
        integral_term := 0.0;
        proportional_term := 0.0;
        derivative_term := 0.0;
        controller_output := 0.0;
        previous_error := error_normalized;

    10:
        proportional_term := Kp * error_normalized;

        IF Td > 0.0 THEN
            derivative_term :=
                Kp * Td * (error_normalized - previous_error)
                / cycle_seconds;
        ELSE
            derivative_term := 0.0;
        END_IF;

        IF Ti > 0.0 THEN
            integral_candidate :=
                integral_term
                + Kp * error_normalized * cycle_seconds / Ti;
        ELSE
            integral_term := 0.0;
            integral_candidate := 0.0;
        END_IF;

        output_candidate :=
            proportional_term + integral_candidate + derivative_term;

        (* Conditional integration: reject updates causing saturation.
           Preserve the integral while the requested output is clamped. *)
        IF (output_candidate >= 0.0) AND (output_candidate <= 1.0) THEN
            integral_term := integral_candidate;
        END_IF;

        controller_output :=
            proportional_term + integral_term + derivative_term;

        IF controller_output > 1.0 THEN
            controller_output := 1.0;
        ELSIF controller_output < 0.0 THEN
            controller_output := 0.0;
        END_IF;

        FillValve :=
            REAL_TO_INT(controller_output * INT_TO_REAL(FULL_SCALE));
        DischargeValve :=
            REAL_TO_INT(0.4 * INT_TO_REAL(FULL_SCALE));

        fill_valve := TRUE;
        discharge_valve := TRUE;
        previous_error := error_normalized;

ELSE
    state_number := 0;
    integral_term := 0.0;
    controller_output := 0.0;
END_CASE;

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

    h_span : REAL := 10.0;
    h_target : REAL;
    h_sp : REAL;
    h_max : REAL;
    eps : REAL;
    t_h : TIME := T#10s;

    (* Initial tuning values; tune for the actual tank. *)
    Kp : REAL := 2.0;
    Ti : REAL := 5.0;
    Td : REAL := 0.0;

    start : BOOL;
    stop : BOOL;
    settled : BOOL;
    r : INT;
    fill_valve : BOOL;
    discharge_valve : BOOL;
END_VAR

h_target := 0.8 * h_span;
h_sp := h_target;
h_max := 0.9 * h_span;
eps := 0.02 * h_span;

controller(
    StartCommand := StartCommand,
    StopCommand := StopCommand,
    LevelMeter := LevelMeter,
    FULL_SCALE := FULL_SCALE,
    h_span := h_span,
    h_sp := h_sp,
    h_target := h_target,
    h_max := h_max,
    eps := eps,
    t_h := t_h,
    Kp := Kp,
    Ti := Ti,
    Td := Td
);

FillValve := controller.FillValve;
DischargeValve := controller.DischargeValve;

start := controller.start;
stop := controller.stop;
settled := controller.settled;
r := controller.r;
fill_valve := controller.fill_valve;
discharge_valve := controller.discharge_valve;

END_PROGRAM


CONFIGURATION Config0
    RESOURCE Res0 ON PLC
        (* Must match cycle_seconds in LevelControl. *)
        TASK ControlTask(INTERVAL := T#20ms, PRIORITY := 0);
        PROGRAM MainInstance WITH ControlTask : Main;
    END_RESOURCE
END_CONFIGURATION
