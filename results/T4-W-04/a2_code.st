FUNCTION_BLOCK FB_LevelControl
VAR_INPUT
    StartCommand : BOOL;
    StopCommand : BOOL;
    LevelMeter : INT;
    h_span : REAL := 10.0;
    Kp : REAL := 10.0;
    Ti : REAL := 10.0;
    Td : REAL := 0.0;
    t_h : TIME := T#10s;
    cycle_seconds : REAL := 0.02;
END_VAR
VAR_OUTPUT
    FillValve : INT;
    DischargeValve : INT;
    fill_valve : BOOL;
    discharge_valve : BOOL;
END_VAR
VAR CONSTANT
    FULL_SCALE : INT := 1000;
    REGION_LOW : INT := 0;
    REGION_MIDDLE : INT := 1;
    REGION_HIGH : INT := 2;
END_VAR
VAR
    StartEdge : R_TRIG;
    HoldTimer : TON;
    start : BOOL;
    stop : BOOL;
    settled : BOOL;
    r : INT;
    sequence_state : INT := 0;
    x0 : BOOL := TRUE;
    x1 : BOOL := FALSE;
    h : REAL;
    h_sp : REAL;
    h_target : REAL;
    h_max : REAL;
    eps : REAL;
    e : REAL;
    previous_error : REAL := 0.0;
    derivative_ready : BOOL := FALSE;
    proportional_term : REAL;
    integral_term : REAL := 0.0;
    derivative_term : REAL;
    integral_candidate : REAL;
    demand_candidate : REAL;
    raw_demand : REAL;
    bounded_demand : REAL;
END_VAR

StartEdge(CLK := StartCommand);
start := StartEdge.Q;
stop := StopCommand;

h := INT_TO_REAL(LevelMeter) * h_span / INT_TO_REAL(FULL_SCALE);
h_sp := 0.8 * h_span;
h_target := h_sp;
h_max := 0.9 * h_span;
eps := 0.02 * h_span;
e := h_sp - h;

IF h < h_target THEN
    r := REGION_LOW;
ELSIF h < h_max THEN
    r := REGION_MIDDLE;
ELSE
    r := REGION_HIGH;
END_IF;

HoldTimer(
    IN := (sequence_state = 1) AND NOT stop
          AND (r <> REGION_HIGH) AND (ABS(e) <= eps),
    PT := t_h
);
settled := HoldTimer.Q;

IF stop THEN
    sequence_state := 0;
ELSE
    CASE sequence_state OF
        0:
            IF start AND (r <> REGION_HIGH) THEN
                sequence_state := 1;
            END_IF;
        1:
            IF settled OR (r = REGION_HIGH) THEN
                sequence_state := 0;
            END_IF;
    ELSE
        sequence_state := 0;
    END_CASE;
END_IF;

x0 := sequence_state = 0;
x1 := sequence_state = 1;
fill_valve := x1;
discharge_valve := x1;

FillValve := 0;
DischargeValve := 0;

IF x1 THEN
    proportional_term := Kp * e;
    derivative_term := 0.0;

    IF derivative_ready AND (cycle_seconds > 0.0) THEN
        derivative_term :=
            Kp * Td * (e - previous_error) / cycle_seconds;
    END_IF;

    raw_demand := proportional_term + integral_term + derivative_term;

    (* Suspend integration whenever the PID demand is clamped.
       Reject an integral increment that would itself cause clamping. *)
    IF (raw_demand >= 0.0) AND (raw_demand <= 100.0)
       AND (Ti > 0.0) AND (cycle_seconds > 0.0) THEN
        integral_candidate :=
            integral_term + Kp * e * cycle_seconds / Ti;
        demand_candidate :=
            proportional_term + integral_candidate + derivative_term;

        IF (demand_candidate >= 0.0)
           AND (demand_candidate <= 100.0) THEN
            integral_term := integral_candidate;
            raw_demand := demand_candidate;
        END_IF;
    END_IF;

    IF raw_demand < 0.0 THEN
        bounded_demand := 0.0;
    ELSIF raw_demand > 100.0 THEN
        bounded_demand := 100.0;
    ELSE
        bounded_demand := raw_demand;
    END_IF;

    FillValve := REAL_TO_INT(
        bounded_demand * INT_TO_REAL(FULL_SCALE) / 100.0
    );
    DischargeValve := REAL_TO_INT(0.4 * INT_TO_REAL(FULL_SCALE));

    previous_error := e;
    derivative_ready := TRUE;
ELSE
    integral_term := 0.0;
    previous_error := e;
    derivative_ready := FALSE;
    bounded_demand := 0.0;
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
VAR
    LevelController : FB_LevelControl;
    h_span : REAL := 10.0;
    Kp : REAL := 10.0;
    Ti : REAL := 10.0;
    Td : REAL := 0.0;
    t_h : TIME := T#10s;
END_VAR

(* Kp uses percent opening per level unit; Ti and Td use seconds.
   Initial gain values are commissioning defaults, not tuned plant gains. *)
LevelController(
    StartCommand := StartCommand,
    StopCommand := StopCommand,
    LevelMeter := LevelMeter,
    h_span := h_span,
    Kp := Kp,
    Ti := Ti,
    Td := Td,
    t_h := t_h,
    cycle_seconds := 0.02
);

FillValve := LevelController.FillValve;
DischargeValve := LevelController.DischargeValve;

END_PROGRAM


CONFIGURATION Config0
    RESOURCE Res0 ON PLC
        TASK ControlTask(INTERVAL := T#20ms, PRIORITY := 0);
        PROGRAM MainInstance WITH ControlTask : Main;
    END_RESOURCE
END_CONFIGURATION
