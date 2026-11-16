FUNCTION_BLOCK LevelControlRuntime
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
    valve_percent : REAL;
END_VAR
VAR CONSTANT
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
    (* r encodes LOW = 0, MID = 1, HIGH = 2.
       MID is a standard function name and cannot be an identifier. *)
    r : INT := 0;

    state_id : INT := 0;
    h_target : REAL;
    h_sp : REAL;
    h_max : REAL;
    eps : REAL;
    e : REAL;

    integral_term : REAL := 0.0;
    integral_candidate : REAL;
    proportional_term : REAL;
    derivative_term : REAL;
    previous_h : REAL := 0.0;
    output_candidate : REAL;
END_VAR

start_edge(CLK := StartCommand);
start := start_edge.Q;
stop := StopCommand;

h_target := 0.8 * h_span;
h_sp := h_target;
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

fill_valve := FALSE;
discharge_valve := FALSE;
valve_percent := 0.0;

(* Stop has priority over starting and continued regulation. *)
IF stop THEN
    state_id := 0;
ELSIF (state_id = 0) AND start THEN
    state_id := 1;
    integral_term := 0.0;
    previous_h := h;
END_IF;

hold_timer(
    IN := (state_id = 1) AND NOT stop
          AND (r <> REGION_HIGH) AND (ABS(e) <= eps),
    PT := T#10s
);
settled := hold_timer.Q;

CASE state_id OF
    0:
        integral_term := 0.0;
        previous_h := h;

    1:
        IF stop OR settled OR (r = REGION_HIGH) THEN
            state_id := 0;
            integral_term := 0.0;
            previous_h := h;
        ELSE
            (* PID output is expressed as percent valve opening.
               Derivative on measurement avoids set-point kick.
               Ti <= 0 disables integration; Td <= 0 disables derivative. *)
            proportional_term := Kp * e;
            derivative_term := 0.0;
            integral_candidate := integral_term;

            IF cycle_seconds > 0.0 THEN
                IF Ti > 0.0 THEN
                    integral_candidate := integral_term
                        + Kp * e * cycle_seconds / Ti;
                ELSE
                    integral_candidate := 0.0;
                END_IF;

                IF Td > 0.0 THEN
                    derivative_term := -Kp * Td
                        * (h - previous_h) / cycle_seconds;
                END_IF;
            END_IF;

            output_candidate := proportional_term
                + integral_candidate + derivative_term;

            (* Freeze the stored integral whenever output is clamped. *)
            IF output_candidate > 100.0 THEN
                valve_percent := 100.0;
            ELSIF output_candidate < 0.0 THEN
                valve_percent := 0.0;
            ELSE
                valve_percent := output_candidate;
                integral_term := integral_candidate;
            END_IF;

            IF Ti <= 0.0 THEN
                integral_term := 0.0;
            END_IF;

            previous_h := h;
            fill_valve := TRUE;
            discharge_valve := TRUE;
        END_IF;

ELSE
    state_id := 0;
    integral_term := 0.0;
    previous_h := h;
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
    controller : LevelControlRuntime;

    (* Level units are volts; PID output units are percent opening.
       Initial gains are commissioning values and may require tuning. *)
    h_span : REAL := 10.0;
    Kp : REAL := 20.0;
    Ti : REAL := 5.0;
    Td : REAL := 0.0;

    h : REAL;
    fill_register : REAL;
END_VAR

h := INT_TO_REAL(LevelMeter) * h_span / INT_TO_REAL(FULL_SCALE);

controller(
    StartCommand := StartCommand,
    StopCommand := StopCommand,
    h := h,
    h_span := h_span,
    Kp := Kp,
    Ti := Ti,
    Td := Td,
    cycle_seconds := 0.02
);

FillValve := 0;
DischargeValve := 0;

IF NOT StopCommand THEN
    IF controller.fill_valve THEN
        fill_register := controller.valve_percent
            * INT_TO_REAL(FULL_SCALE) / 100.0;

        IF fill_register < 0.0 THEN
            fill_register := 0.0;
        ELSIF fill_register > INT_TO_REAL(FULL_SCALE) THEN
            fill_register := INT_TO_REAL(FULL_SCALE);
        END_IF;

        FillValve := REAL_TO_INT(fill_register);
    END_IF;

    IF controller.discharge_valve THEN
        DischargeValve := REAL_TO_INT(0.4 * INT_TO_REAL(FULL_SCALE));
    END_IF;
END_IF;

END_PROGRAM


CONFIGURATION Config0
    RESOURCE Res0 ON PLC
        (* Keep this interval consistent with cycle_seconds above. *)
        TASK ControlTask(INTERVAL := T#20ms, PRIORITY := 0);
        PROGRAM MainInstance WITH ControlTask : Main;
    END_RESOURCE
END_CONFIGURATION
