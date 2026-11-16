FUNCTION_BLOCK LevelControl
VAR_INPUT
    StartCommand : BOOL;
    StopCommand : BOOL;
    LevelMeter : INT;
    Kp : REAL := 20.0;
    Ti : REAL := 5.0;
    Td : REAL := 0.0;
END_VAR
VAR_OUTPUT
    FillValve : INT;
    DischargeValve : INT;
    fill_valve : BOOL;
    discharge_valve : BOOL;
END_VAR
VAR CONSTANT
    FULL_SCALE : INT := 1000;
    h_span : REAL := 10.0;
    h_sp : REAL := 8.0;
    h_target : REAL := 8.0;
    h_max : REAL := 9.0;
    eps : REAL := 0.2;
    t_h : TIME := T#10s;
    scan_seconds : REAL := 0.02;
    region_low : INT := 0;
    region_middle : INT := 1;
    region_high : INT := 2;
END_VAR
VAR
    start_edge : R_TRIG;
    hold_timer : TON;
    start : BOOL;
    stop : BOOL;
    settled : BOOL;
    r : INT;
    sequence_state : INT := 0;
    x0 : BOOL;
    x1 : BOOL;
    h : REAL;
    e : REAL;
    previous_error : REAL := 0.0;
    integral_term : REAL := 0.0;
    proposed_integral : REAL;
    proportional_term : REAL;
    derivative_term : REAL;
    raw_demand : REAL;
    bounded_demand : REAL;
    pid_initialized : BOOL := FALSE;
END_VAR

(* This block must execute once every 20 ms. Ti and Td are in seconds;
   Kp is in percent valve opening per volt of level error. *)
start_edge(CLK := StartCommand);
start := start_edge.Q;
stop := StopCommand;

h := INT_TO_REAL(LevelMeter) * h_span / INT_TO_REAL(FULL_SCALE);
e := h_sp - h;

IF h < h_target THEN
    r := region_low;
ELSIF h < h_max THEN
    r := region_middle;
ELSE
    r := region_high;
END_IF;

(* The hold condition measures uninterrupted time in the tolerance band,
   and is reset outside regulation or whenever the band is left. *)
hold_timer(
    IN := (sequence_state = 1) AND
          NOT stop AND
          (r <> region_high) AND
          (ABS(e) <= eps),
    PT := t_h
);
settled := hold_timer.Q;

IF stop THEN
    sequence_state := 0;
ELSE
    CASE sequence_state OF
        0:
            IF start AND (r <> region_high) THEN
                sequence_state := 1;
            END_IF;
        1:
            IF settled OR (r = region_high) THEN
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

IF fill_valve THEN
    IF NOT pid_initialized THEN
        integral_term := 0.0;
        previous_error := e;
        pid_initialized := TRUE;
    END_IF;

    proportional_term := Kp * e;
    derivative_term := Kp * Td * (e - previous_error) / scan_seconds;

    proposed_integral := integral_term;
    IF Ti > 0.0 THEN
        proposed_integral :=
            integral_term + Kp * e * scan_seconds / Ti;
    ELSE
        (* A nonpositive Ti disables the integral component. *)
        integral_term := 0.0;
        proposed_integral := 0.0;
    END_IF;

    raw_demand :=
        proportional_term + proposed_integral + derivative_term;

    (* Suspend integration whenever the proposed output is clamped. *)
    IF raw_demand > 100.0 THEN
        bounded_demand := 100.0;
    ELSIF raw_demand < 0.0 THEN
        bounded_demand := 0.0;
    ELSE
        bounded_demand := raw_demand;
        integral_term := proposed_integral;
    END_IF;

    previous_error := e;
    FillValve := REAL_TO_INT(
        bounded_demand * INT_TO_REAL(FULL_SCALE) / 100.0
    );
ELSE
    pid_initialized := FALSE;
    integral_term := 0.0;
    previous_error := e;
    bounded_demand := 0.0;
END_IF;

IF discharge_valve THEN
    DischargeValve := REAL_TO_INT(0.4 * INT_TO_REAL(FULL_SCALE));
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
    controller : LevelControl;
    Kp : REAL := 20.0;
    Ti : REAL := 5.0;
    Td : REAL := 0.0;
END_VAR

controller(
    StartCommand := StartCommand,
    StopCommand := StopCommand,
    LevelMeter := LevelMeter,
    Kp := Kp,
    Ti := Ti,
    Td := Td
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
