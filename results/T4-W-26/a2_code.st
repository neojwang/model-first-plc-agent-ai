FUNCTION_BLOCK FB_LevelControl
VAR_INPUT
    StartCommand : BOOL;
    StopCommand : BOOL;
    LevelMeter : INT;
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
VAR CONSTANT
    FULL_SCALE : INT := 1000;
    h_span : REAL := 10.0;
    h_target : REAL := 8.0;
    h_sp : REAL := 8.0;
    h_max : REAL := 9.0;
    eps : REAL := 0.2;
    t_h : TIME := T#10s;
    cycle_seconds : REAL := 0.02;
    region_low : INT := 0;
    region_mid : INT := 1;
    region_high : INT := 2;
END_VAR
VAR
    start_edge : R_TRIG;
    hold_timer : TON;
    start : BOOL;
    stop : BOOL;
    settled : BOOL;
    r : INT;
    state_number : INT := 0;
    previous_state : INT;
    h : REAL;
    error_value : REAL;
    previous_error : REAL := 0.0;
    proportional_term : REAL;
    integral_term : REAL := 0.0;
    candidate_integral : REAL;
    derivative_term : REAL;
    raw_demand : REAL;
    bounded_demand : REAL;
END_VAR

(* The calling task must execute every 20 ms.
   PID output units are percent; Ti and Td are in seconds. *)
start_edge(CLK := StartCommand);
start := start_edge.Q;
stop := StopCommand;

h := INT_TO_REAL(LevelMeter) * h_span / INT_TO_REAL(FULL_SCALE);
error_value := h_sp - h;

IF h < h_target THEN
    r := region_low;
ELSIF h < h_max THEN
    r := region_mid;
ELSE
    r := region_high;
END_IF;

(* Count only uninterrupted in-band time during active regulation. *)
hold_timer(
    IN := (state_number = 1)
          AND NOT stop
          AND (r <> region_high)
          AND (ABS(error_value) <= eps),
    PT := t_h
);
settled := hold_timer.Q;

previous_state := state_number;

IF stop THEN
    state_number := 0;
ELSE
    CASE state_number OF
        0:
            IF start AND (r <> region_high) THEN
                state_number := 1;
            END_IF;
        1:
            IF settled OR (r = region_high) THEN
                state_number := 0;
            END_IF;
    ELSE
        state_number := 0;
    END_CASE;
END_IF;

fill_valve := state_number = 1;
discharge_valve := state_number = 1;

FillValve := 0;
DischargeValve := 0;

IF fill_valve THEN
    (* Restart the PID without a derivative kick. *)
    IF previous_state <> 1 THEN
        integral_term := 0.0;
        previous_error := error_value;
    END_IF;

    proportional_term := Kp * error_value;

    derivative_term := 0.0;
    IF Td > 0.0 THEN
        derivative_term :=
            Kp * Td * (error_value - previous_error) / cycle_seconds;
    END_IF;

    candidate_integral := integral_term;
    IF Ti > 0.0 THEN
        candidate_integral :=
            integral_term + Kp * error_value * cycle_seconds / Ti;
    ELSE
        integral_term := 0.0;
        candidate_integral := 0.0;
    END_IF;

    raw_demand :=
        proportional_term + candidate_integral + derivative_term;

    (* Reject the integration increment whenever the demand is clamped. *)
    IF raw_demand > 100.0 THEN
        bounded_demand := 100.0;
    ELSIF raw_demand < 0.0 THEN
        bounded_demand := 0.0;
    ELSE
        bounded_demand := raw_demand;
        integral_term := candidate_integral;
    END_IF;

    previous_error := error_value;

    FillValve := REAL_TO_INT(
        bounded_demand * INT_TO_REAL(FULL_SCALE) / 100.0
    );
    DischargeValve := REAL_TO_INT(0.4 * INT_TO_REAL(FULL_SCALE));
ELSE
    integral_term := 0.0;
    previous_error := error_value;
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
    controller : FB_LevelControl;
    (* Initial tuning values; commission against the simulated plant. *)
    Kp : REAL := 20.0;
    Ti : REAL := 10.0;
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
