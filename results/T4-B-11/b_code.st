FUNCTION_BLOCK LevelControl
VAR_INPUT
    StartCommand : BOOL;
    StopCommand : BOOL;
    LevelMeter : INT;
    FULL_SCALE : INT;
    h_span : REAL;
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
VAR
    StartEdge : R_TRIG;
    HoldTimer : TON;

    start : BOOL;
    stop : BOOL;
    settled : BOOL;

    (* Region encoding: 0 = LOW, 1 = MID, 2 = HIGH.
       MID is a standard function name, so it is not an identifier. *)
    r : INT := 0;

    control_state : INT := 0;
    previous_state : INT := 0;

    h : REAL;
    h_sp : REAL;
    h_target : REAL;
    h_max : REAL;
    eps : REAL;
    e : REAL;

    integral_term : REAL := 0.0;
    candidate_integral : REAL;
    derivative_term : REAL;
    previous_error : REAL := 0.0;
    proportional_term : REAL;
    raw_output : REAL;
    limited_output : REAL;

    (* Must match the MainTask interval below. *)
    cycle_seconds : REAL := 0.02;
END_VAR

StartEdge(CLK := StartCommand);
start := StartEdge.Q;
stop := StopCommand;

h_target := 0.8 * h_span;
h_sp := h_target;
h_max := 0.9 * h_span;
eps := 0.02 * h_span;

IF FULL_SCALE > 0 THEN
    h := INT_TO_REAL(LevelMeter) * h_span / INT_TO_REAL(FULL_SCALE);
ELSE
    h := 0.0;
END_IF;

e := h_sp - h;

IF h < h_target THEN
    r := 0; (* LOW *)
ELSIF h < h_max THEN
    r := 1; (* MID *)
ELSE
    r := 2; (* HIGH *)
END_IF;

HoldTimer(
    IN := (control_state = 1) AND NOT stop
          AND (r <> 2) AND (ABS(e) <= eps),
    PT := T#10s
);
settled := HoldTimer.Q;

previous_state := control_state;

IF stop THEN
    control_state := 0;
ELSE
    CASE control_state OF
        0:
            IF start AND (r <> 2) THEN
                control_state := 1;
            END_IF;

        1:
            IF settled OR (r = 2) THEN
                control_state := 0;
            END_IF;

        ELSE
            control_state := 0;
    END_CASE;
END_IF;

(* Safe defaults apply in the initial step and on every stop. *)
FillValve := 0;
DischargeValve := 0;
fill_valve := FALSE;
discharge_valve := FALSE;

CASE control_state OF
    0:
        integral_term := 0.0;
        previous_error := e;
        limited_output := 0.0;

    1:
        fill_valve := TRUE;
        discharge_valve := TRUE;

        IF previous_state <> 1 THEN
            integral_term := 0.0;
            previous_error := e;
        END_IF;

        (* PID output is expressed in percent of valve opening.
           Kp: percent per level unit; Ti and Td: seconds. *)
        proportional_term := Kp * e;
        derivative_term :=
            Kp * Td * (e - previous_error) / cycle_seconds;

        IF Ti > 0.0 THEN
            candidate_integral :=
                integral_term + Kp * e * cycle_seconds / Ti;
        ELSE
            integral_term := 0.0;
            candidate_integral := 0.0;
        END_IF;

        raw_output :=
            proportional_term + candidate_integral + derivative_term;

        (* Conditional integration: reject the integral update whenever
           the resulting controller output would be clamped. *)
        IF raw_output > 100.0 THEN
            limited_output := 100.0;
        ELSIF raw_output < 0.0 THEN
            limited_output := 0.0;
        ELSE
            integral_term := candidate_integral;
            limited_output := raw_output;
        END_IF;

        previous_error := e;

        IF FULL_SCALE > 0 THEN
            FillValve := REAL_TO_INT(
                limited_output * INT_TO_REAL(FULL_SCALE) / 100.0
            );
            DischargeValve := REAL_TO_INT(
                0.4 * INT_TO_REAL(FULL_SCALE)
            );
        END_IF;

    ELSE
        integral_term := 0.0;
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
    Controller : LevelControl;

    (* Level engineering units are volts across the measuring span. *)
    h_span : REAL := 10.0;

    (* Initial tuning values; adjust for the actual tank dynamics. *)
    Kp : REAL := 40.0;
    Ti : REAL := 5.0;
    Td : REAL := 0.0;
END_VAR

Controller(
    StartCommand := StartCommand,
    StopCommand := StopCommand,
    LevelMeter := LevelMeter,
    FULL_SCALE := FULL_SCALE,
    h_span := h_span,
    Kp := Kp,
    Ti := Ti,
    Td := Td
);

FillValve := Controller.FillValve;
DischargeValve := Controller.DischargeValve;

END_PROGRAM


CONFIGURATION Config0
    RESOURCE Res0 ON PLC
        TASK MainTask(INTERVAL := T#20ms, PRIORITY := 0);
        PROGRAM MainInstance WITH MainTask : Main;
    END_RESOURCE
END_CONFIGURATION
