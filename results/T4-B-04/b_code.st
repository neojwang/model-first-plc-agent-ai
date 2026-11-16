FUNCTION_BLOCK LevelControl
VAR_INPUT
    StartCommand : BOOL;
    StopCommand : BOOL;
    LevelMeter : INT;
    full_scale_value : INT;
    h_span : REAL;
    Kp : REAL;
    Ti : REAL;
    Td : REAL;
    sample_time : REAL;
END_VAR
VAR_OUTPUT
    fill_valve : BOOL := FALSE;
    discharge_valve : BOOL := FALSE;
    fill_command : INT := 0;
    discharge_command : INT := 0;
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

    state_number : INT := 0;
    h : REAL;
    h_target : REAL;
    h_max : REAL;
    eps : REAL;
    error_value : REAL;
    previous_error : REAL := 0.0;
    integral_value : REAL := 0.0;
    integral_candidate : REAL;
    proportional_value : REAL;
    derivative_value : REAL;
    output_candidate : REAL;
    output_percent : REAL;
END_VAR

start_edge(CLK := StartCommand);
start := start_edge.Q;
stop := StopCommand;

(* Convert the analog register to engineering units (volts). *)
h := INT_TO_REAL(LevelMeter) * h_span / INT_TO_REAL(full_scale_value);
h_target := 0.8 * h_span;
h_max := 0.9 * h_span;
eps := 0.02 * h_span;
error_value := h_target - h;

IF h < h_target THEN
    r := 0;
ELSIF h < h_max THEN
    r := 1;
ELSE
    r := 2;
END_IF;

(* Stop has priority over starting. *)
IF stop THEN
    state_number := 0;
ELSIF (state_number = 0) AND start THEN
    state_number := 1;
    integral_value := 0.0;
    previous_error := error_value;
END_IF;

hold_timer(
    IN := (state_number = 1) AND NOT stop
          AND (ABS(error_value) <= eps),
    PT := T#10s
);
settled := hold_timer.Q;

IF (state_number = 1) AND (settled OR (r = 2)) THEN
    state_number := 0;
END_IF;

(* Safe defaults, including the initial state. *)
fill_valve := FALSE;
discharge_valve := FALSE;
fill_command := 0;
discharge_command := 0;

CASE state_number OF
    0:
        integral_value := 0.0;
        previous_error := error_value;

    1:
        fill_valve := TRUE;
        discharge_valve := TRUE;

        (* Kp is percent opening per engineering unit.
           Ti, Td and sample_time are in seconds.
           A nonpositive Ti disables integral action. *)
        proportional_value := Kp * error_value;
        derivative_value := 0.0;

        IF (Td > 0.0) AND (sample_time > 0.0) THEN
            derivative_value :=
                Kp * Td * (error_value - previous_error) / sample_time;
        END_IF;

        output_percent :=
            proportional_value + integral_value + derivative_value;

        (* Suspend integration whenever the output is clamped.
           Also reject an integral update that would cause saturation. *)
        IF Ti <= 0.0 THEN
            integral_value := 0.0;
        ELSIF (sample_time > 0.0)
              AND (output_percent >= 0.0)
              AND (output_percent <= 100.0) THEN
            integral_candidate :=
                integral_value + Kp * error_value * sample_time / Ti;
            output_candidate :=
                proportional_value + integral_candidate + derivative_value;

            IF (output_candidate >= 0.0)
               AND (output_candidate <= 100.0) THEN
                integral_value := integral_candidate;
            END_IF;
        END_IF;

        output_percent :=
            proportional_value + integral_value + derivative_value;

        IF output_percent > 100.0 THEN
            output_percent := 100.0;
        ELSIF output_percent < 0.0 THEN
            output_percent := 0.0;
        END_IF;

        fill_command :=
            REAL_TO_INT(output_percent * INT_TO_REAL(full_scale_value) / 100.0);
        discharge_command :=
            REAL_TO_INT(0.4 * INT_TO_REAL(full_scale_value));

        previous_error := error_value;

ELSE
    state_number := 0;
    integral_value := 0.0;
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
    h_span : REAL := 10.0;
    sample_time : REAL := 0.1;
END_VAR
VAR
    controller : LevelControl;

    (* Initial tuning values; adjust for the actual plant. *)
    Kp : REAL := 20.0;
    Ti : REAL := 10.0;
    Td : REAL := 0.0;
END_VAR

controller(
    StartCommand := StartCommand,
    StopCommand := StopCommand,
    LevelMeter := LevelMeter,
    full_scale_value := FULL_SCALE,
    h_span := h_span,
    Kp := Kp,
    Ti := Ti,
    Td := Td,
    sample_time := sample_time
);

FillValve := controller.fill_command;
DischargeValve := controller.discharge_command;

END_PROGRAM


CONFIGURATION Config0
RESOURCE Res0 ON PLC
    TASK ControlTask(INTERVAL := T#100ms, PRIORITY := 0);
    PROGRAM MainInstance WITH ControlTask : Main;
END_RESOURCE
END_CONFIGURATION
