FUNCTION_BLOCK FB_LevelControl
VAR_INPUT
    StartCommand : BOOL;
    StopCommand : BOOL;
    LevelMeter : INT;
    h_span : REAL := 10.0;
    t_h : TIME := T#10s;
    Kp : REAL := 1.0;
    Ti : REAL := 10.0;
    Td : REAL := 0.0;
    cycle_time_s : REAL := 0.02;
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
    REGION_MID : INT := 1;
    REGION_HIGH : INT := 2;
END_VAR

VAR
    start_edge : R_TRIG;
    hold_timer : TON;

    start : BOOL;
    stop : BOOL;
    settled : BOOL;
    r : INT;

    state_no : INT := 0;
    x0 : BOOL := TRUE;
    x1 : BOOL := FALSE;

    h : REAL;
    h_sp : REAL;
    h_target : REAL;
    h_max : REAL;
    eps : REAL;
    e : REAL;

    integral_term : REAL := 0.0;
    previous_error : REAL := 0.0;
    derivative_term : REAL;
    proportional_term : REAL;
    integral_candidate : REAL;
    candidate_output : REAL;
    raw_output : REAL;
    bounded_output : REAL;
    error_valid : BOOL := FALSE;
END_VAR

(* Start is a single-scan rising-edge event, including during stop. *)
start_edge(CLK := StartCommand);
start := start_edge.Q;
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
    r := REGION_MID;
ELSE
    r := REGION_HIGH;
END_IF;

(* Stop dominates start and all regulation actions. *)
IF stop THEN
    state_no := 0;
ELSE
    CASE state_no OF
        0:
            IF start THEN
                state_no := 1;
            END_IF;

        1:
            state_no := 1;

    ELSE
        state_no := 0;
    END_CASE;
END_IF;

(* The hold interval is continuous time inside the tolerance band.
   The timer resets outside regulation or outside the band. *)
hold_timer(
    IN := (state_no = 1) AND NOT stop AND (ABS(e) <= eps),
    PT := t_h
);
settled := hold_timer.Q;

IF state_no = 1 THEN
    IF stop OR settled OR (r = REGION_HIGH) THEN
        state_no := 0;
    END_IF;
END_IF;

x0 := state_no = 0;
x1 := state_no = 1;

fill_valve := x1;
discharge_valve := x1;

(* Default outputs are zero, including in initial step 0. *)
FillValve := 0;
DischargeValve := 0;

IF x1 THEN
    (* Parallel PID with normalized valve demand: 0.0 through 1.0.
       Ti and Td are expressed in seconds. Ti <= 0 disables integration. *)
    proportional_term := Kp * e;
    derivative_term := 0.0;

    IF error_valid AND (cycle_time_s > 0.0) AND (Td > 0.0) THEN
        derivative_term :=
            Kp * Td * (e - previous_error) / cycle_time_s;
    END_IF;

    raw_output := proportional_term + integral_term + derivative_term;

    (* Integrate only if neither the present nor proposed output is
       clamped. Otherwise retain the integral state unchanged. *)
    IF (Ti > 0.0) AND (cycle_time_s > 0.0)
       AND (raw_output >= 0.0) AND (raw_output <= 1.0) THEN
        integral_candidate :=
            integral_term + Kp * e * cycle_time_s / Ti;
        candidate_output :=
            proportional_term + integral_candidate + derivative_term;

        IF (candidate_output >= 0.0) AND (candidate_output <= 1.0) THEN
            integral_term := integral_candidate;
        END_IF;
    END_IF;

    raw_output := proportional_term + integral_term + derivative_term;

    IF raw_output > 1.0 THEN
        bounded_output := 1.0;
    ELSIF raw_output < 0.0 THEN
        bounded_output := 0.0;
    ELSE
        bounded_output := raw_output;
    END_IF;

    FillValve :=
        REAL_TO_INT(bounded_output * INT_TO_REAL(FULL_SCALE));
    DischargeValve :=
        REAL_TO_INT(0.4 * INT_TO_REAL(FULL_SCALE));

    previous_error := e;
    error_valid := TRUE;
ELSE
    integral_term := 0.0;
    previous_error := e;
    error_valid := FALSE;
    settled := FALSE;
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
    level_controller : FB_LevelControl;

    h_span : REAL := 10.0;
    t_h : TIME := T#10s;

    (* Initial gain settings; tune for the simulated plant. *)
    Kp : REAL := 1.0;
    Ti : REAL := 10.0;
    Td : REAL := 0.0;
END_VAR

level_controller(
    StartCommand := StartCommand,
    StopCommand := StopCommand,
    LevelMeter := LevelMeter,
    h_span := h_span,
    t_h := t_h,
    Kp := Kp,
    Ti := Ti,
    Td := Td,
    cycle_time_s := 0.02
);

FillValve := level_controller.FillValve;
DischargeValve := level_controller.DischargeValve;

END_PROGRAM


CONFIGURATION Config0
    RESOURCE Res0 ON PLC
        TASK MainTask(INTERVAL := T#20ms, PRIORITY := 0);
        PROGRAM MainInstance WITH MainTask : Main;
    END_RESOURCE
END_CONFIGURATION
