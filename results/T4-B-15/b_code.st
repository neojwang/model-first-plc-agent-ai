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
    t_h : TIME;
    cycle_seconds : REAL;
END_VAR
VAR_OUTPUT
    FillCommand : INT;
    DischargeCommand : INT;
    fill_valve : BOOL;
    discharge_valve : BOOL;
END_VAR
VAR
    start_edge : R_TRIG;
    hold_timer : TON;

    start : BOOL;
    stop : BOOL;
    settled : BOOL;

    (* Region encoding: 0 = LOW, 1 = MID, 2 = HIGH.
       MID is not declared as an identifier because it is reserved. *)
    r : INT := 0;

    phase_index : INT := 0;

    h : REAL;
    h_sp : REAL;
    h_target : REAL;
    h_max : REAL;
    eps : REAL;
    e : REAL;
    previous_error : REAL := 0.0;

    integral_term : REAL := 0.0;
    proportional_term : REAL;
    derivative_term : REAL;
    integral_candidate : REAL;
    candidate_output : REAL;
    raw_output : REAL;
    limited_output : REAL;
END_VAR

start_edge(CLK := StartCommand);
start := start_edge.Q;
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
    r := 0;
ELSIF h < h_max THEN
    r := 1;
ELSE
    r := 2;
END_IF;

(* Stop has priority over every state transition. *)
IF stop THEN
    phase_index := 0;
ELSE
    CASE phase_index OF
        0:
            IF start THEN
                phase_index := 1;
                integral_term := 0.0;
                previous_error := e;
            END_IF;

        1:
            (* Regulation and completion are evaluated below. *)
            phase_index := 1;

    ELSE
        phase_index := 0;
    END_CASE;
END_IF;

(* Calling TON every scan also resets it whenever regulation ends. *)
hold_timer(
    IN := (phase_index = 1)
          AND NOT stop
          AND (r <> 2)
          AND (ABS(e) <= eps),
    PT := t_h
);
settled := hold_timer.Q;

IF (phase_index = 1) AND (settled OR (r = 2)) THEN
    phase_index := 0;
END_IF;

(* Safe defaults: step 0 always closes both valves. *)
FillCommand := 0;
DischargeCommand := 0;
fill_valve := FALSE;
discharge_valve := FALSE;

IF (phase_index = 1)
   AND NOT stop
   AND (FULL_SCALE > 0)
   AND (cycle_seconds > 0.0) THEN

    fill_valve := TRUE;
    discharge_valve := TRUE;

    (* PID output units are percent valve opening.
       Kp is percent per level unit; Ti and Td are in seconds. *)
    proportional_term := Kp * e;
    derivative_term := Kp * Td * (e - previous_error) / cycle_seconds;

    IF Ti <= 0.0 THEN
        integral_term := 0.0;
    END_IF;

    raw_output := proportional_term + integral_term + derivative_term;

    (* Suspend integration at either output limit. Also reject an
       integration increment that would cross either limit. *)
    IF (Ti > 0.0) AND (raw_output > 0.0) AND (raw_output < 100.0) THEN
        integral_candidate :=
            integral_term + Kp * e * cycle_seconds / Ti;

        candidate_output :=
            proportional_term + integral_candidate + derivative_term;

        IF (candidate_output >= 0.0) AND (candidate_output <= 100.0) THEN
            integral_term := integral_candidate;
            raw_output := candidate_output;
        END_IF;
    END_IF;

    IF raw_output < 0.0 THEN
        limited_output := 0.0;
    ELSIF raw_output > 100.0 THEN
        limited_output := 100.0;
    ELSE
        limited_output := raw_output;
    END_IF;

    FillCommand :=
        REAL_TO_INT(limited_output * INT_TO_REAL(FULL_SCALE) / 100.0);
    DischargeCommand :=
        REAL_TO_INT(0.4 * INT_TO_REAL(FULL_SCALE));

    previous_error := e;
ELSE
    integral_term := 0.0;
    previous_error := e;
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

    h_span : REAL := 10.0;
    Kp : REAL := 20.0;
    Ti : REAL := 5.0;
    Td : REAL := 0.0;
    t_h : TIME := T#10s;

    (* Must match the cyclic task interval below. *)
    cycle_seconds : REAL := 0.1;
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
    t_h := t_h,
    cycle_seconds := cycle_seconds
);

FillValve := controller.FillCommand;
DischargeValve := controller.DischargeCommand;

END_PROGRAM


CONFIGURATION Config0
    RESOURCE Res0 ON PLC
        TASK ControlTask(INTERVAL := T#100ms, PRIORITY := 0);
        PROGRAM MainInstance WITH ControlTask : Main;
    END_RESOURCE
END_CONFIGURATION
