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
    cycle_seconds : REAL;
    t_h : TIME;
END_VAR
VAR_OUTPUT
    FillValve : INT;
    DischargeValve : INT;
    start : BOOL;
    stop : BOOL;
    settled : BOOL;
    r : INT; (* 0 = LOW, 1 = MID, 2 = HIGH *)
    fill_valve : BOOL;
    discharge_valve : BOOL;
END_VAR
VAR
    StartEdge : R_TRIG;
    HoldTimer : TON;
    state_index : INT := 0;
    h : REAL;
    h_target : REAL;
    h_sp : REAL;
    h_max : REAL;
    eps : REAL;
    e : REAL;
    previous_error : REAL := 0.0;
    integral_term : REAL := 0.0;
    derivative_term : REAL;
    proportional_term : REAL;
    candidate_integral : REAL;
    candidate_output : REAL;
    raw_output : REAL;
    output_percent : REAL;
    in_band : BOOL;
END_VAR

StartEdge(CLK := StartCommand);
start := StartEdge.Q;
stop := StopCommand;

(* Work in volts: the measuring span is 10 V. *)
h := INT_TO_REAL(LevelMeter) * h_span / INT_TO_REAL(FULL_SCALE);
h_target := 0.8 * h_span;
h_sp := h_target;
h_max := 0.9 * h_span;
eps := 0.02 * h_span;
e := h_sp - h;

IF h < h_target THEN
    r := 0; (* LOW *)
ELSIF h < h_max THEN
    r := 1; (* MID *)
ELSE
    r := 2; (* HIGH *)
END_IF;

FillValve := 0;
DischargeValve := 0;
fill_valve := FALSE;
discharge_valve := FALSE;

(* Stop has priority over a simultaneous start event. *)
IF stop THEN
    state_index := 0;
ELSIF (state_index = 0) AND start THEN
    state_index := 1;
    integral_term := 0.0;
    previous_error := e;
END_IF;

in_band := ABS(e) <= eps;
HoldTimer(
    IN := (state_index = 1) AND in_band AND NOT stop,
    PT := t_h
);
settled := HoldTimer.Q;

IF (state_index = 1) AND (settled OR (r = 2)) THEN
    state_index := 0;
END_IF;

CASE state_index OF
    0:
        (* Initial/idle state: both valve commands remain zero. *)
        integral_term := 0.0;
        previous_error := e;

    1:
        fill_valve := TRUE;
        discharge_valve := TRUE;

        (* Parallel PID; Kp is expressed in percent opening per volt.
           Ti and Td are expressed in seconds. *)
        proportional_term := Kp * e;
        derivative_term := 0.0;

        IF (Td > 0.0) AND (cycle_seconds > 0.0) THEN
            derivative_term :=
                Kp * Td * (e - previous_error) / cycle_seconds;
        END_IF;

        IF Ti <= 0.0 THEN
            integral_term := 0.0;
        END_IF;

        raw_output :=
            proportional_term + integral_term + derivative_term;

        (* Conditional integration: freeze the integral whenever the
           unconstrained output is saturated. Reject an integration
           increment that would itself push the output beyond a limit. *)
        IF (Ti > 0.0) AND (cycle_seconds > 0.0)
           AND (raw_output >= 0.0) AND (raw_output <= 100.0) THEN
            candidate_integral :=
                integral_term + Kp * e * cycle_seconds / Ti;
            candidate_output :=
                proportional_term + candidate_integral + derivative_term;

            IF (candidate_output >= 0.0)
               AND (candidate_output <= 100.0) THEN
                integral_term := candidate_integral;
                raw_output := candidate_output;
            END_IF;
        END_IF;

        IF raw_output < 0.0 THEN
            output_percent := 0.0;
        ELSIF raw_output > 100.0 THEN
            output_percent := 100.0;
        ELSE
            output_percent := raw_output;
        END_IF;

        FillValve := REAL_TO_INT(
            output_percent * INT_TO_REAL(FULL_SCALE) / 100.0
        );
        DischargeValve := REAL_TO_INT(
            0.4 * INT_TO_REAL(FULL_SCALE)
        );

        previous_error := e;

ELSE
    state_index := 0;
    integral_term := 0.0;
    previous_error := e;
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
    h_span : REAL := 10.0;
    Kp : REAL := 20.0;
    Ti : REAL := 5.0;
    Td : REAL := 0.0;
    t_h : TIME := T#10s;
    start : BOOL;
    stop : BOOL;
    settled : BOOL;
    r : INT;
    fill_valve : BOOL;
    discharge_valve : BOOL;
END_VAR

Controller(
    StartCommand := StartCommand,
    StopCommand := StopCommand,
    LevelMeter := LevelMeter,
    FULL_SCALE := FULL_SCALE,
    h_span := h_span,
    Kp := Kp,
    Ti := Ti,
    Td := Td,
    cycle_seconds := 0.02,
    t_h := t_h
);

FillValve := Controller.FillValve;
DischargeValve := Controller.DischargeValve;

start := Controller.start;
stop := Controller.stop;
settled := Controller.settled;
r := Controller.r;
fill_valve := Controller.fill_valve;
discharge_valve := Controller.discharge_valve;

END_PROGRAM


CONFIGURATION Config0
    RESOURCE Res0 ON PLC
        TASK ControlTask(INTERVAL := T#20ms, PRIORITY := 0);
        PROGRAM MainInstance WITH ControlTask : Main;
    END_RESOURCE
END_CONFIGURATION
