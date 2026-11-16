FUNCTION_BLOCK LevelControl
VAR_INPUT
    StartCommand : BOOL;
    StopCommand : BOOL;
    h : REAL;
    h_span : REAL;
    Kp : REAL;
    Ti : REAL;
    Td : REAL;
    cycle_seconds : REAL;
END_VAR
VAR_OUTPUT
    fill_valve : BOOL;
    discharge_valve : BOOL;
    fill_percent : REAL;
    discharge_percent : REAL;
END_VAR
VAR
    start_trigger : R_TRIG;
    hold_timer : TON;

    start : BOOL;
    stop : BOOL;
    settled : BOOL;

    (* Region encoding: 0 = LOW, 1 = MID, 2 = HIGH.
       MID is not declared as an identifier because it is reserved. *)
    r : INT := 0;

    control_state : INT := 0;
    h_target : REAL;
    h_sp : REAL;
    h_max : REAL;
    eps : REAL;
    t_h : TIME := T#10s;

    e : REAL;
    previous_error : REAL := 0.0;
    integral_term : REAL := 0.0;
    derivative_term : REAL;
    integral_increment : REAL;
    candidate_integral : REAL;
    candidate_output : REAL;
    raw_output : REAL;
END_VAR

start_trigger(CLK := StartCommand);
start := start_trigger.Q;
stop := StopCommand;

h_target := 0.8 * h_span;
h_sp := h_target;
h_max := 0.9 * h_span;
eps := 0.02 * h_span;
e := h_sp - h;

IF h < h_target THEN
    r := 0;
ELSIF h < h_max THEN
    r := 1;
ELSE
    r := 2;
END_IF;

hold_timer(
    IN := (control_state = 1)
          AND NOT stop
          AND (r <> 2)
          AND (ABS(e) <= eps),
    PT := t_h
);
settled := hold_timer.Q;

(* Safe defaults apply in the initial state and on every termination. *)
fill_valve := FALSE;
discharge_valve := FALSE;
fill_percent := 0.0;
discharge_percent := 0.0;

IF stop THEN
    control_state := 0;
    integral_term := 0.0;
    previous_error := e;
ELSE
    IF control_state = 0 THEN
        IF start AND (r <> 2) THEN
            integral_term := 0.0;
            previous_error := e;
            control_state := 1;
        END_IF;
    END_IF;

    CASE control_state OF
        0:
            integral_term := 0.0;
            previous_error := e;

        1:
            IF settled OR (r = 2) THEN
                control_state := 0;
                integral_term := 0.0;
                previous_error := e;
            ELSE
                fill_valve := TRUE;
                discharge_valve := TRUE;
                discharge_percent := 40.0;

                derivative_term := 0.0;
                IF (Td > 0.0) AND (cycle_seconds > 0.0) THEN
                    derivative_term :=
                        Kp * Td * (e - previous_error) / cycle_seconds;
                END_IF;

                raw_output := Kp * e
                              + integral_term
                              + derivative_term;

                (* Conditional integration: freeze the integrator while
                   clamped, and reject an update that would cause clamping. *)
                IF (Ti > 0.0) AND (cycle_seconds > 0.0) THEN
                    IF (raw_output >= 0.0) AND (raw_output <= 100.0) THEN
                        integral_increment :=
                            Kp * e * cycle_seconds / Ti;
                        candidate_integral :=
                            integral_term + integral_increment;
                        candidate_output :=
                            Kp * e + candidate_integral + derivative_term;

                        IF (candidate_output >= 0.0)
                           AND (candidate_output <= 100.0) THEN
                            integral_term := candidate_integral;
                            raw_output := candidate_output;
                        END_IF;
                    END_IF;
                END_IF;

                IF raw_output > 100.0 THEN
                    fill_percent := 100.0;
                ELSIF raw_output < 0.0 THEN
                    fill_percent := 0.0;
                ELSE
                    fill_percent := raw_output;
                END_IF;

                previous_error := e;
            END_IF;

        ELSE
            control_state := 0;
            integral_term := 0.0;
            previous_error := e;
    END_CASE;
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

    (* Commissioning defaults: Kp in percent/V, Ti and Td in seconds. *)
    Kp : REAL := 25.0;
    Ti : REAL := 5.0;
    Td : REAL := 0.0;
    cycle_seconds : REAL := 0.02;
END_VAR
VAR
    controller : LevelControl;
    initialized : BOOL := FALSE;
    measured_level : REAL;
END_VAR

IF NOT initialized THEN
    FillValve := 0;
    DischargeValve := 0;
    initialized := TRUE;
END_IF;

measured_level :=
    INT_TO_REAL(LevelMeter) * h_span / INT_TO_REAL(FULL_SCALE);

controller(
    StartCommand := StartCommand,
    StopCommand := StopCommand,
    h := measured_level,
    h_span := h_span,
    Kp := Kp,
    Ti := Ti,
    Td := Td,
    cycle_seconds := cycle_seconds
);

FillValve := 0;
DischargeValve := 0;

IF controller.fill_valve AND NOT StopCommand THEN
    FillValve := REAL_TO_INT(
        controller.fill_percent * INT_TO_REAL(FULL_SCALE) / 100.0
    );
END_IF;

IF controller.discharge_valve AND NOT StopCommand THEN
    DischargeValve := REAL_TO_INT(
        controller.discharge_percent * INT_TO_REAL(FULL_SCALE) / 100.0
    );
END_IF;
END_PROGRAM


CONFIGURATION Config0
    RESOURCE Res0 ON PLC
        TASK ControlTask(INTERVAL := T#20ms, PRIORITY := 0);
        PROGRAM MainInstance WITH ControlTask : Main;
    END_RESOURCE
END_CONFIGURATION
