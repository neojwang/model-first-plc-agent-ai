FUNCTION_BLOCK LevelControl
VAR_INPUT
    StartCommand : BOOL;
    StopCommand : BOOL;
    LevelMeter : INT;
    FULL_SCALE : INT := 1000;
    Kp : REAL := 20.0;       (* PID gain: percent opening per volt *)
    Ti : REAL := 5.0;        (* Integral time in seconds; <= 0 disables integration *)
    Td : REAL := 0.0;        (* Derivative time in seconds *)
END_VAR

VAR_OUTPUT
    FillValve : INT;
    DischargeValve : INT;
    fill_valve : BOOL;
    discharge_valve : BOOL;
END_VAR

VAR CONSTANT
    h_span : REAL := 10.0;
    t_h : TIME := T#10s;
    sample_seconds : REAL := 0.02;  (* Must match the configured task interval *)
END_VAR

VAR
    StartEdge : R_TRIG;
    HoldTimer : TON;

    start : BOOL;
    stop : BOOL;
    settled : BOOL;

    (* Region encoding: 0 = LOW, 1 = MID, 2 = HIGH.
       Numeric encoding avoids the reserved standard function name MID. *)
    r : INT := 0;

    phase_index : INT := 0;
    h : REAL;
    h_target : REAL;
    h_sp : REAL;
    h_max : REAL;
    eps : REAL;
    e : REAL;

    integral_term : REAL := 0.0;
    previous_error : REAL := 0.0;
    proportional_term : REAL;
    derivative_term : REAL;
    candidate_integral : REAL;
    candidate_output : REAL;
    raw_output : REAL;
    pid_output : REAL := 0.0;
    first_pid_scan : BOOL := TRUE;
END_VAR

StartEdge(CLK := StartCommand);
start := StartEdge.Q;
stop := StopCommand;

h_target := 0.8 * h_span;
h_sp := h_target;
h_max := 0.9 * h_span;
eps := 0.02 * h_span;

h := INT_TO_REAL(LevelMeter) * h_span / INT_TO_REAL(FULL_SCALE);
e := h_sp - h;

IF h < h_target THEN
    r := 0;                       (* LOW *)
ELSIF h < h_max THEN
    r := 1;                       (* MID *)
ELSE
    r := 2;                       (* HIGH *)
END_IF;

(* Stop has priority over starting and regulation. *)
IF stop THEN
    phase_index := 0;
ELSIF (phase_index = 0) AND start THEN
    phase_index := 1;
    integral_term := 0.0;
    first_pid_scan := TRUE;
END_IF;

HoldTimer(
    IN := (phase_index = 1) AND NOT stop AND (ABS(e) <= eps),
    PT := t_h
);
settled := HoldTimer.Q;

FillValve := 0;
DischargeValve := 0;
fill_valve := FALSE;
discharge_valve := FALSE;

CASE phase_index OF
    0:
        pid_output := 0.0;

    1:
        IF stop OR settled OR (r = 2) THEN
            phase_index := 0;
        ELSE
            fill_valve := TRUE;
            discharge_valve := TRUE;

            proportional_term := Kp * e;

            IF first_pid_scan THEN
                previous_error := e;
                first_pid_scan := FALSE;
            END_IF;

            derivative_term :=
                Kp * Td * (e - previous_error) / sample_seconds;
            previous_error := e;

            IF Ti <= 0.0 THEN
                integral_term := 0.0;
            END_IF;

            raw_output :=
                proportional_term + integral_term + derivative_term;

            (* Suspend integration whenever the output is saturated.
               Also reject an integration increment that would saturate it. *)
            IF (Ti > 0.0)
                AND (raw_output > 0.0)
                AND (raw_output < 100.0) THEN

                candidate_integral :=
                    integral_term + Kp * e * sample_seconds / Ti;

                candidate_output :=
                    proportional_term + candidate_integral + derivative_term;

                IF (candidate_output >= 0.0)
                    AND (candidate_output <= 100.0) THEN
                    integral_term := candidate_integral;
                    raw_output := candidate_output;
                END_IF;
            END_IF;

            IF raw_output < 0.0 THEN
                pid_output := 0.0;
            ELSIF raw_output > 100.0 THEN
                pid_output := 100.0;
            ELSE
                pid_output := raw_output;
            END_IF;

            FillValve := REAL_TO_INT(
                pid_output * INT_TO_REAL(FULL_SCALE) / 100.0
            );
            DischargeValve := REAL_TO_INT(
                0.4 * INT_TO_REAL(FULL_SCALE)
            );
        END_IF;

ELSE
    phase_index := 0;
END_CASE;

(* Reset controller memory and close both valves immediately on return to idle. *)
IF phase_index = 0 THEN
    integral_term := 0.0;
    previous_error := 0.0;
    first_pid_scan := TRUE;
    pid_output := 0.0;
    FillValve := 0;
    DischargeValve := 0;
    fill_valve := FALSE;
    discharge_valve := FALSE;
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
    Controller : LevelControl;
    Kp : REAL := 20.0;
    Ti : REAL := 5.0;
    Td : REAL := 0.0;
END_VAR

Controller(
    StartCommand := StartCommand,
    StopCommand := StopCommand,
    LevelMeter := LevelMeter,
    FULL_SCALE := FULL_SCALE,
    Kp := Kp,
    Ti := Ti,
    Td := Td
);

FillValve := Controller.FillValve;
DischargeValve := Controller.DischargeValve;

END_PROGRAM


CONFIGURATION Config0
    RESOURCE Res0 ON PLC
        TASK ControlTask(INTERVAL := T#20ms, PRIORITY := 0);
        PROGRAM MainInstance WITH ControlTask : Main;
    END_RESOURCE
END_CONFIGURATION
