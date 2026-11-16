FUNCTION_BLOCK LevelControl
VAR_INPUT
    StartCommand : BOOL;
    StopCommand : BOOL;
    LevelMeter : INT;
    FULL_SCALE : INT;
    Kp : REAL := 25.0;       (* Percent valve opening per volt of error. *)
    Ti : REAL := 10.0;       (* Integral time, seconds; <= 0 disables integration. *)
    Td : REAL := 0.0;        (* Derivative time, seconds. *)
END_VAR

VAR_OUTPUT
    FillValve : INT;
    DischargeValve : INT;
    fill_valve : BOOL;
    discharge_valve : BOOL;
END_VAR

VAR CONSTANT
    h_span : REAL := 10.0;
    h_target : REAL := 8.0;
    h_sp : REAL := 8.0;
    h_max : REAL := 9.0;
    eps : REAL := 0.2;
    t_h : TIME := T#10s;
    sample_seconds : REAL := 0.1;
END_VAR

VAR
    start_edge : R_TRIG;
    hold_timer : TON;

    start : BOOL;
    stop : BOOL;
    settled : BOOL;

    (* Region encoding: 0 = LOW, 1 = MID, 2 = HIGH.
       MID is not used as an identifier because it is a standard function. *)
    r : INT := 0;

    state_index : INT := 0;
    h : REAL;
    e : REAL;
    previous_error : REAL := 0.0;
    first_pid_scan : BOOL := TRUE;

    proportional_term : REAL;
    integral_term : REAL := 0.0;
    derivative_term : REAL;
    integral_increment : REAL;
    candidate_integral : REAL;
    candidate_output : REAL;
    unrestricted_output : REAL;
    pid_output : REAL;
END_VAR

start_edge(CLK := StartCommand);
start := start_edge.Q;
stop := StopCommand;

IF FULL_SCALE > 0 THEN
    h := INT_TO_REAL(LevelMeter) * h_span / INT_TO_REAL(FULL_SCALE);
ELSE
    h := 0.0;
END_IF;

e := h_sp - h;

IF h < h_target THEN
    r := 0;
ELSIF h < h_max THEN
    r := 1;
ELSE
    r := 2;
END_IF;

(* Default to closed valves, including idle and invalid states. *)
FillValve := 0;
DischargeValve := 0;
fill_valve := FALSE;
discharge_valve := FALSE;

IF stop OR (FULL_SCALE <= 0) THEN
    state_index := 0;
ELSIF (state_index = 0) AND start THEN
    state_index := 1;
    integral_term := 0.0;
    previous_error := e;
    first_pid_scan := TRUE;
END_IF;

(* A single TON measures uninterrupted residence inside the tolerance band. *)
hold_timer(
    IN := (state_index = 1)
          AND NOT stop
          AND (FULL_SCALE > 0)
          AND (r <> 2)
          AND (ABS(e) <= eps),
    PT := t_h
);
settled := hold_timer.Q;

CASE state_index OF
    0:
        integral_term := 0.0;
        previous_error := e;
        first_pid_scan := TRUE;
        pid_output := 0.0;

    1:
        IF stop OR settled OR (r = 2) OR (FULL_SCALE <= 0) THEN
            state_index := 0;
            integral_term := 0.0;
            previous_error := e;
            first_pid_scan := TRUE;
            pid_output := 0.0;
        ELSE
            (* Discrete PID, executed by the 100 ms task below.
               Integral state is explicitly held whenever output is clamped. *)
            proportional_term := Kp * e;

            IF first_pid_scan THEN
                derivative_term := 0.0;
                first_pid_scan := FALSE;
            ELSE
                derivative_term :=
                    Kp * Td * (e - previous_error) / sample_seconds;
            END_IF;

            IF Ti <= 0.0 THEN
                integral_term := 0.0;
            END_IF;

            unrestricted_output :=
                proportional_term + integral_term + derivative_term;

            IF unrestricted_output > 100.0 THEN
                pid_output := 100.0;
            ELSIF unrestricted_output < 0.0 THEN
                pid_output := 0.0;
            ELSE
                pid_output := unrestricted_output;

                IF Ti > 0.0 THEN
                    integral_increment :=
                        Kp * e * sample_seconds / Ti;
                    candidate_integral :=
                        integral_term + integral_increment;
                    candidate_output :=
                        proportional_term
                        + candidate_integral
                        + derivative_term;

                    (* Reject integration that would cause saturation. *)
                    IF (candidate_output >= 0.0)
                       AND (candidate_output <= 100.0) THEN
                        integral_term := candidate_integral;
                        pid_output := candidate_output;
                    END_IF;
                END_IF;
            END_IF;

            previous_error := e;

            fill_valve := TRUE;
            discharge_valve := TRUE;

            FillValve := REAL_TO_INT(
                pid_output * INT_TO_REAL(FULL_SCALE) / 100.0
            );
            DischargeValve := REAL_TO_INT(
                0.4 * INT_TO_REAL(FULL_SCALE)
            );
        END_IF;

ELSE
    state_index := 0;
    integral_term := 0.0;
    previous_error := e;
    first_pid_scan := TRUE;
    pid_output := 0.0;
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
    Kp : REAL := 25.0;
    Ti : REAL := 10.0;
    Td : REAL := 0.0;
END_VAR

controller(
    StartCommand := StartCommand,
    StopCommand := StopCommand,
    LevelMeter := LevelMeter,
    FULL_SCALE := FULL_SCALE,
    Kp := Kp,
    Ti := Ti,
    Td := Td
);

FillValve := controller.FillValve;
DischargeValve := controller.DischargeValve;

END_PROGRAM


CONFIGURATION Config0
    RESOURCE Res0 ON PLC
        TASK ControlTask(INTERVAL := T#100ms, PRIORITY := 0);
        PROGRAM MainInstance WITH ControlTask : Main;
    END_RESOURCE
END_CONFIGURATION
