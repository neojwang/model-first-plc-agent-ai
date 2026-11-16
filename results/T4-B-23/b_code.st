FUNCTION_BLOCK LevelControl
VAR_INPUT
    StartCommand : BOOL;
    StopCommand : BOOL;
    LevelMeter : INT;
    FULL_SCALE : INT;
    h_span : REAL;
    Kp : REAL;
    Ti : REAL; (* Integral time, seconds; <= 0 disables integration. *)
    Td : REAL; (* Derivative time, seconds; <= 0 disables derivative. *)
    cycle_seconds : REAL;
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
    REGION_LOW : INT := 0;
    REGION_MID : INT := 1; (* MID region; MID is a reserved standard function. *)
    REGION_HIGH : INT := 2;
END_VAR
VAR
    start_edge : R_TRIG;
    hold_timer : TON;
    control_state : INT := 0;
    h : REAL;
    h_sp : REAL;
    h_target : REAL;
    h_max : REAL;
    eps : REAL;
    e : REAL;
    previous_error : REAL := 0.0;
    previous_valid : BOOL := FALSE;
    proportional_term : REAL;
    integral_term : REAL := 0.0;
    derivative_term : REAL;
    integral_candidate : REAL;
    raw_output : REAL;
    trial_output : REAL;
    pid_output : REAL;
    in_band : BOOL;
END_VAR

start_edge(CLK := StartCommand);
start := start_edge.Q;
stop := StopCommand;

h_sp := 0.8 * h_span;
h_target := h_sp;
h_max := 0.9 * h_span;
eps := 0.02 * h_span;

IF FULL_SCALE > 0 THEN
    h := INT_TO_REAL(LevelMeter) * h_span / INT_TO_REAL(FULL_SCALE);
ELSE
    h := 0.0;
END_IF;

e := h_sp - h;

IF h < h_target THEN
    r := REGION_LOW;
ELSIF h < h_max THEN
    r := REGION_MID;
ELSE
    r := REGION_HIGH;
END_IF;

FillValve := 0;
DischargeValve := 0;
fill_valve := FALSE;
discharge_valve := FALSE;

IF stop THEN
    control_state := 0;
ELSIF (control_state = 0) AND start THEN
    control_state := 1;
    integral_term := 0.0;
    previous_valid := FALSE;
END_IF;

IF (control_state = 1) AND (r = REGION_HIGH) THEN
    control_state := 0;
END_IF;

in_band := (control_state = 1) AND NOT stop AND (ABS(e) <= eps);
hold_timer(IN := in_band, PT := T#10s);
settled := hold_timer.Q;

IF settled THEN
    control_state := 0;
END_IF;

CASE control_state OF
    0:
        integral_term := 0.0;
        previous_error := e;
        previous_valid := FALSE;

    1:
        (* PID output is expressed as percent valve opening. *)
        proportional_term := Kp * e;
        derivative_term := 0.0;

        IF previous_valid AND (Td > 0.0) AND (cycle_seconds > 0.0) THEN
            derivative_term :=
                Kp * Td * (e - previous_error) / cycle_seconds;
        END_IF;

        IF Ti <= 0.0 THEN
            integral_term := 0.0;
        END_IF;

        raw_output := proportional_term + integral_term + derivative_term;

        (* Freeze integration whenever the output is clamped.
           Also reject an integral update that would cause clamping. *)
        IF (Ti > 0.0) AND (cycle_seconds > 0.0)
           AND (raw_output >= 0.0) AND (raw_output <= 100.0) THEN
            integral_candidate :=
                integral_term + Kp * e * cycle_seconds / Ti;
            trial_output :=
                proportional_term + integral_candidate + derivative_term;

            IF (trial_output >= 0.0) AND (trial_output <= 100.0) THEN
                integral_term := integral_candidate;
            END_IF;
        END_IF;

        raw_output := proportional_term + integral_term + derivative_term;

        IF raw_output < 0.0 THEN
            pid_output := 0.0;
        ELSIF raw_output > 100.0 THEN
            pid_output := 100.0;
        ELSE
            pid_output := raw_output;
        END_IF;

        previous_error := e;
        previous_valid := TRUE;

        fill_valve := TRUE;
        discharge_valve := TRUE;

        IF FULL_SCALE > 0 THEN
            FillValve :=
                REAL_TO_INT(pid_output * INT_TO_REAL(FULL_SCALE) / 100.0);
            DischargeValve :=
                REAL_TO_INT(0.4 * INT_TO_REAL(FULL_SCALE));
        END_IF;

ELSE
    control_state := 0;
    integral_term := 0.0;
    previous_valid := FALSE;
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
    h_span : REAL := 10.0;
    cycle_seconds : REAL := 0.02;
END_VAR
VAR
    (* Initial tuning: Kp in percent/volt; Ti and Td in seconds. *)
    Kp : REAL := 20.0;
    Ti : REAL := 5.0;
    Td : REAL := 0.0;
    controller : LevelControl;
END_VAR

controller(
    StartCommand := StartCommand,
    StopCommand := StopCommand,
    LevelMeter := LevelMeter,
    FULL_SCALE := FULL_SCALE,
    h_span := h_span,
    Kp := Kp,
    Ti := Ti,
    Td := Td,
    cycle_seconds := cycle_seconds
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
