FUNCTION_BLOCK LevelControl
VAR_INPUT
    StartCommand : BOOL;
    StopCommand : BOOL;
    LevelMeter : INT;
    FULL_SCALE : INT;
    h_span : REAL;
    h_sp : REAL;
    h_target : REAL;
    h_max : REAL;
    eps : REAL;
    t_h : TIME;
    Kp : REAL;
    Ti : REAL;
    Td : REAL;
    CycleSeconds : REAL;
END_VAR
VAR_OUTPUT
    FillValve : INT;
    DischargeValve : INT;
    fill_valve : BOOL;
    discharge_valve : BOOL;
END_VAR
VAR
    StartEdge : R_TRIG;
    HoldTimer : TON;
    start : BOOL;
    stop : BOOL;
    settled : BOOL;

    (* Level region encoding: 0 = LOW, 1 = MID, 2 = HIGH.
       MID is a standard function name, so it is not declared. *)
    r : INT;

    StateNumber : INT := 0;
    h : REAL;
    e : REAL;
    PreviousError : REAL := 0.0;
    IntegralTerm : REAL := 0.0;
    DerivativeTerm : REAL;
    RawOutput : REAL;
    LimitedOutput : REAL;
END_VAR

StartEdge(CLK := StartCommand);
start := StartEdge.Q;
stop := StopCommand;

h := INT_TO_REAL(LevelMeter) * h_span / INT_TO_REAL(FULL_SCALE);
e := h_sp - h;

IF h < h_target THEN
    r := 0;
ELSIF h < h_max THEN
    r := 1;
ELSE
    r := 2;
END_IF;

HoldTimer(
    IN := (StateNumber = 1) AND NOT stop
          AND (r <> 2) AND (ABS(e) <= eps),
    PT := t_h
);
settled := HoldTimer.Q;

(* Safe defaults apply to the idle state and every stopping condition. *)
FillValve := 0;
DischargeValve := 0;
fill_valve := FALSE;
discharge_valve := FALSE;

IF stop THEN
    StateNumber := 0;
    IntegralTerm := 0.0;
    PreviousError := e;
ELSE
    CASE StateNumber OF
        0:
            IntegralTerm := 0.0;
            PreviousError := e;

            IF start AND (r <> 2) THEN
                StateNumber := 1;
            END_IF;

        1:
            IF settled OR (r = 2) THEN
                StateNumber := 0;
                IntegralTerm := 0.0;
                PreviousError := e;
            ELSE
                DerivativeTerm := 0.0;
                IF CycleSeconds > 0.0 THEN
                    DerivativeTerm :=
                        Kp * Td * (e - PreviousError) / CycleSeconds;
                END_IF;

                RawOutput := Kp * e + IntegralTerm + DerivativeTerm;

                IF RawOutput > 100.0 THEN
                    LimitedOutput := 100.0;
                ELSIF RawOutput < 0.0 THEN
                    LimitedOutput := 0.0;
                ELSE
                    LimitedOutput := RawOutput;
                END_IF;

                (* Conditional integration: freeze the integrator while
                   the controller output is at either saturation limit.
                   The updated integral is used on the next scan. *)
                IF (RawOutput > 0.0) AND (RawOutput < 100.0)
                   AND (Ti > 0.0) AND (CycleSeconds > 0.0) THEN
                    IntegralTerm :=
                        IntegralTerm + Kp * e * CycleSeconds / Ti;
                END_IF;

                PreviousError := e;

                fill_valve := TRUE;
                discharge_valve := TRUE;
                FillValve := REAL_TO_INT(
                    LimitedOutput * INT_TO_REAL(FULL_SCALE) / 100.0
                );
                DischargeValve := REAL_TO_INT(
                    0.4 * INT_TO_REAL(FULL_SCALE)
                );
            END_IF;

        ELSE
            StateNumber := 0;
            IntegralTerm := 0.0;
            PreviousError := e;
    END_CASE;
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
    h_span : REAL := 10.0;
    h_sp : REAL := 8.0;
    h_target : REAL := 8.0;
    h_max : REAL := 9.0;
    eps : REAL := 0.2;
    t_h : TIME := T#10s;
    CycleSeconds : REAL := 0.02;
END_VAR
VAR
    (* Initial tuning values; adjust for the simulated plant.
       Kp is percent valve opening per volt; Ti and Td are seconds. *)
    Kp : REAL := 25.0;
    Ti : REAL := 20.0;
    Td : REAL := 0.0;
    Controller : LevelControl;
END_VAR

Controller(
    StartCommand := StartCommand,
    StopCommand := StopCommand,
    LevelMeter := LevelMeter,
    FULL_SCALE := FULL_SCALE,
    h_span := h_span,
    h_sp := h_sp,
    h_target := h_target,
    h_max := h_max,
    eps := eps,
    t_h := t_h,
    Kp := Kp,
    Ti := Ti,
    Td := Td,
    CycleSeconds := CycleSeconds
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
