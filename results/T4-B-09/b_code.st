FUNCTION_BLOCK FB_LevelControl
VAR_INPUT
    start       : BOOL;
    stop        : BOOL;
    level_raw   : INT;
    scale_value : INT;
    h_span      : REAL;
    Kp          : REAL;
    Ti          : REAL;
    Td          : REAL;
    cycle_time  : TIME;
    cycle_s     : REAL;
END_VAR
VAR_OUTPUT
    fill_valve      : BOOL;
    discharge_valve : BOOL;
    fill_command    : INT;
    discharge_command : INT;
    settled         : BOOL;
    (* Region encoding: 0 = LOW, 1 = MID, 2 = HIGH.
       MID is not declared as an identifier because it is an IEC function. *)
    r               : INT;
END_VAR
VAR
    state_number    : INT := 0;
    hold_timer      : TON;
    h               : REAL;
    h_target        : REAL;
    h_max           : REAL;
    eps             : REAL;
    error_value     : REAL;
    previous_error  : REAL := 0.0;
    integral_value  : REAL := 0.0;
    integral_trial  : REAL;
    proportional    : REAL;
    derivative      : REAL;
    output_trial    : REAL;
    output_fraction : REAL;
END_VAR

h := INT_TO_REAL(level_raw) * h_span / INT_TO_REAL(scale_value);
h_target := 0.8 * h_span;
h_max := 0.9 * h_span;
eps := 0.02 * h_span;
error_value := h_target - h;

IF h < h_target THEN
    r := 0;                         (* LOW *)
ELSIF h < h_max THEN
    r := 1;                         (* MID *)
ELSE
    r := 2;                         (* HIGH *)
END_IF;

fill_valve := FALSE;
discharge_valve := FALSE;
fill_command := 0;
discharge_command := 0;

(* Stop has priority over a simultaneous start event. *)
IF stop THEN
    state_number := 0;
ELSIF (state_number = 0) AND start THEN
    state_number := 1;
    integral_value := 0.0;
    previous_error := error_value;
END_IF;

hold_timer(
    IN := (state_number = 1)
          AND NOT stop
          AND (ABS(error_value) <= eps),
    PT := T#10s
);
settled := hold_timer.Q;

CASE state_number OF
    0:
        integral_value := 0.0;
        previous_error := error_value;

    1:
        IF stop OR settled OR (r = 2) THEN
            state_number := 0;
            integral_value := 0.0;
            previous_error := error_value;
        ELSE
            proportional := Kp * error_value;

            derivative := 0.0;
            IF (Td > 0.0) AND (cycle_s > 0.0) THEN
                derivative := Kp * Td
                              * (error_value - previous_error)
                              / cycle_s;
            END_IF;

            integral_trial := integral_value;
            IF (Ti > 0.0) AND (cycle_s > 0.0) THEN
                integral_trial := integral_value
                                  + Kp * error_value * cycle_s / Ti;
            END_IF;

            output_trial := proportional + integral_trial + derivative;

            (* Commit integration only when the trial output is not
               saturated. While clamped, retain the previous integral. *)
            IF output_trial > 1.0 THEN
                output_fraction := 1.0;
            ELSIF output_trial < 0.0 THEN
                output_fraction := 0.0;
            ELSE
                output_fraction := output_trial;
                integral_value := integral_trial;
            END_IF;

            previous_error := error_value;

            fill_valve := TRUE;
            discharge_valve := TRUE;
            fill_command := REAL_TO_INT(
                output_fraction * INT_TO_REAL(scale_value)
            );
            discharge_command := REAL_TO_INT(
                0.4 * INT_TO_REAL(scale_value)
            );
        END_IF;

ELSE
    state_number := 0;
    integral_value := 0.0;
    previous_error := error_value;
END_CASE;

END_FUNCTION_BLOCK


PROGRAM Main
VAR
    StartCommand   AT %IX100.0 : BOOL;
    StopCommand    AT %IX100.1 : BOOL;
    LevelMeter     AT %IW100   : INT;
    FillValve      AT %QW100   : INT;
    DischargeValve AT %QW101   : INT;
END_VAR
VAR CONSTANT
    FULL_SCALE : INT := 1000;
END_VAR
VAR
    (* Gains are initial tuning values; output is a fraction of full opening,
       and level/error are expressed in volts. Ti and Td are in seconds. *)
    h_span          : REAL := 10.0;
    Kp              : REAL := 0.5;
    Ti              : REAL := 5.0;
    Td              : REAL := 0.0;

    start           : BOOL;
    stop            : BOOL;
    settled         : BOOL;
    r               : INT;
    fill_valve      : BOOL;
    discharge_valve : BOOL;

    start_edge      : R_TRIG;
    controller      : FB_LevelControl;
END_VAR

start_edge(CLK := StartCommand);
start := start_edge.Q;
stop := StopCommand;

controller(
    start := start,
    stop := stop,
    level_raw := LevelMeter,
    scale_value := FULL_SCALE,
    h_span := h_span,
    Kp := Kp,
    Ti := Ti,
    Td := Td,
    cycle_time := T#20ms,
    cycle_s := 0.02
);

settled := controller.settled;
r := controller.r;
fill_valve := controller.fill_valve;
discharge_valve := controller.discharge_valve;

FillValve := controller.fill_command;
DischargeValve := controller.discharge_command;

END_PROGRAM


CONFIGURATION Config0
    RESOURCE Res0 ON PLC
        TASK ControlTask(INTERVAL := T#20ms, PRIORITY := 0);
        PROGRAM MainInstance WITH ControlTask : Main;
    END_RESOURCE
END_CONFIGURATION
