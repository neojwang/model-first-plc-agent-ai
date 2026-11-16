FUNCTION_BLOCK LevelControl
VAR_INPUT
    StartCommand : BOOL;
    StopCommand : BOOL;
    LevelMeter : INT;
    Kp : REAL := 20.0;
    Ti : REAL := 5.0;
    Td : REAL := 0.0;
    h_span : REAL := 10.0;
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
END_VAR
VAR
    StartEdge : R_TRIG;
    HoldTimer : TON;

    start : BOOL;
    stop : BOOL;
    settled : BOOL;
    r : INT := 0; (* 0 = LOW, 1 = MID, 2 = HIGH *)

    StateCode : INT := 0;
    x0 : BOOL := TRUE;
    x1 : BOOL := FALSE;

    h : REAL;
    h_sp : REAL;
    h_target : REAL;
    h_max : REAL;
    eps : REAL;
    error_value : REAL;

    IntegralTerm : REAL := 0.0;
    CandidateIntegral : REAL;
    PreviousError : REAL := 0.0;
    DerivativeRate : REAL;
    ProportionalDerivative : REAL;
    CandidateOutput : REAL;
    RawOutput : REAL;
    LimitedOutput : REAL;
    HistoryValid : BOOL := FALSE;
END_VAR

StartEdge(CLK := StartCommand);
start := StartEdge.Q;
stop := StopCommand;

h := INT_TO_REAL(LevelMeter) * h_span / INT_TO_REAL(FULL_SCALE);
h_sp := 0.8 * h_span;
h_target := h_sp;
h_max := 0.9 * h_span;
eps := 0.02 * h_span;
error_value := h_sp - h;

IF h < h_target THEN
    r := 0;
ELSIF h < h_max THEN
    r := 1;
ELSE
    r := 2;
END_IF;

HoldTimer(
    IN := (StateCode = 1)
          AND NOT stop
          AND (r <> 2)
          AND (ABS(error_value) <= eps),
    PT := t_h
);
settled := HoldTimer.Q;

IF stop THEN
    StateCode := 0;
ELSE
    CASE StateCode OF
        0:
            IF start AND (r <> 2) THEN
                StateCode := 1;
            END_IF;
        1:
            IF settled OR (r = 2) THEN
                StateCode := 0;
            END_IF;
    ELSE
        StateCode := 0;
    END_CASE;
END_IF;

x0 := StateCode = 0;
x1 := StateCode = 1;
fill_valve := x1;
discharge_valve := x1;

FillValve := 0;
DischargeValve := 0;

IF x1 THEN
    DerivativeRate := 0.0;
    IF HistoryValid AND (cycle_seconds > 0.0) THEN
        DerivativeRate :=
            (error_value - PreviousError) / cycle_seconds;
    END_IF;

    ProportionalDerivative :=
        Kp * (error_value + Td * DerivativeRate);

    CandidateIntegral := IntegralTerm;
    IF (Ti > 0.0) AND (cycle_seconds > 0.0) THEN
        CandidateIntegral :=
            IntegralTerm + Kp * error_value * cycle_seconds / Ti;
    END_IF;

    CandidateOutput := ProportionalDerivative + CandidateIntegral;

    (* Reject integration whenever the proposed output would be clamped. *)
    IF (CandidateOutput >= 0.0) AND (CandidateOutput <= 100.0) THEN
        IntegralTerm := CandidateIntegral;
    END_IF;

    RawOutput := ProportionalDerivative + IntegralTerm;

    IF RawOutput > 100.0 THEN
        LimitedOutput := 100.0;
    ELSIF RawOutput < 0.0 THEN
        LimitedOutput := 0.0;
    ELSE
        LimitedOutput := RawOutput;
    END_IF;

    FillValve :=
        REAL_TO_INT(LimitedOutput * INT_TO_REAL(FULL_SCALE) / 100.0);
    DischargeValve :=
        REAL_TO_INT(0.4 * INT_TO_REAL(FULL_SCALE));

    PreviousError := error_value;
    HistoryValid := TRUE;
ELSE
    IntegralTerm := 0.0;
    PreviousError := error_value;
    HistoryValid := FALSE;
    DerivativeRate := 0.0;
    RawOutput := 0.0;
    LimitedOutput := 0.0;
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
    Controller : LevelControl;
    Kp : REAL := 20.0;
    Ti : REAL := 5.0;
    Td : REAL := 0.0;
    h_span : REAL := 10.0;
    t_h : TIME := T#10s;
END_VAR

Controller(
    StartCommand := StartCommand,
    StopCommand := StopCommand,
    LevelMeter := LevelMeter,
    Kp := Kp,
    Ti := Ti,
    Td := Td,
    h_span := h_span,
    t_h := t_h,
    cycle_seconds := 0.02
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
