FUNCTION_BLOCK TankLevelRuntime
VAR_INPUT
    StartCommand : BOOL;
    StopCommand : BOOL;
    LevelMeter : INT;
    FULL_SCALE : INT;
    Kp : REAL;
    Ti : REAL;
    Td : REAL;
    CycleSeconds : REAL;
    t_h : TIME;
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

    x0 : BOOL := TRUE;
    x1 : BOOL := FALSE;
    WasRegulating : BOOL;

    start : BOOL;
    stop : BOOL;
    settled : BOOL;
    r : INT;

    h : REAL;
    h_target : REAL;
    h_max : REAL;
    eps : REAL;
    ErrorValue : REAL;
    NormalizedError : REAL;

    PreviousError : REAL := 0.0;
    IntegralTerm : REAL := 0.0;
    ProportionalTerm : REAL;
    DerivativeTerm : REAL;
    CandidateIntegral : REAL;
    CandidateDemand : REAL;
    RawDemand : REAL;
    BoundedDemand : REAL;
END_VAR

(* Region codes: 0 = LOW, 1 = MID, 2 = HIGH. *)
StartEdge(CLK := StartCommand);
start := StartEdge.Q;
stop := StopCommand;

h := INT_TO_REAL(LevelMeter);
h_target := 0.8 * INT_TO_REAL(FULL_SCALE);
h_max := 0.9 * INT_TO_REAL(FULL_SCALE);
eps := 0.02 * INT_TO_REAL(FULL_SCALE);
ErrorValue := h_target - h;

IF h < h_target THEN
    r := 0;
ELSIF h < h_max THEN
    r := 1;
ELSE
    r := 2;
END_IF;

(* Measure uninterrupted residence inside the tolerance band in x1. *)
HoldTimer(
    IN := x1 AND NOT stop AND (ABS(ErrorValue) <= eps),
    PT := t_h
);
settled := HoldTimer.Q;

(* Evaluate transitions from the situation at scan entry. *)
WasRegulating := x1;

IF x0 THEN
    IF start AND NOT stop AND (r <> 2) THEN
        x0 := FALSE;
        x1 := TRUE;
    END_IF;
ELSIF x1 THEN
    IF stop OR settled OR (r = 2) THEN
        x1 := FALSE;
        x0 := TRUE;
    END_IF;
END_IF;

fill_valve := x1;
discharge_valve := x1;

FillValve := 0;
DischargeValve := 0;

IF fill_valve THEN
    (* Fractional error and fractional valve demand use the same scale.
       Kp is dimensionless; Ti, Td and CycleSeconds are in seconds. *)
    NormalizedError := ErrorValue / INT_TO_REAL(FULL_SCALE);

    IF NOT WasRegulating THEN
        PreviousError := NormalizedError;
    END_IF;

    ProportionalTerm := Kp * NormalizedError;
    DerivativeTerm := 0.0;

    IF CycleSeconds > 0.0 THEN
        DerivativeTerm :=
            Kp * Td * (NormalizedError - PreviousError) / CycleSeconds;
    END_IF;

    RawDemand := ProportionalTerm + IntegralTerm + DerivativeTerm;

    (* Explicit PID integration permits complete integration suspension
       whenever the output is saturated. Integral state is retained
       while regulation is inactive. *)
    IF (Ti > 0.0) AND (CycleSeconds > 0.0)
       AND (RawDemand >= 0.0) AND (RawDemand <= 1.0) THEN
        CandidateIntegral :=
            IntegralTerm + Kp * NormalizedError * CycleSeconds / Ti;
        CandidateDemand :=
            ProportionalTerm + CandidateIntegral + DerivativeTerm;

        IF (CandidateDemand >= 0.0) AND (CandidateDemand <= 1.0) THEN
            IntegralTerm := CandidateIntegral;
            RawDemand := CandidateDemand;
        END_IF;
    END_IF;

    IF RawDemand < 0.0 THEN
        BoundedDemand := 0.0;
    ELSIF RawDemand > 1.0 THEN
        BoundedDemand := 1.0;
    ELSE
        BoundedDemand := RawDemand;
    END_IF;

    PreviousError := NormalizedError;
    FillValve := REAL_TO_INT(BoundedDemand * INT_TO_REAL(FULL_SCALE));
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
VAR CONSTANT
    FULL_SCALE : INT := 1000;
END_VAR
VAR
    Controller : TankLevelRuntime;
    Kp : REAL := 2.0;
    Ti : REAL := 5.0;
    Td : REAL := 0.0;
    t_h : TIME := T#10s;
    CycleSeconds : REAL := 0.02;
END_VAR

Controller(
    StartCommand := StartCommand,
    StopCommand := StopCommand,
    LevelMeter := LevelMeter,
    FULL_SCALE := FULL_SCALE,
    Kp := Kp,
    Ti := Ti,
    Td := Td,
    CycleSeconds := CycleSeconds,
    t_h := t_h
);

FillValve := Controller.FillValve;
DischargeValve := Controller.DischargeValve;

END_PROGRAM


CONFIGURATION Config0
    RESOURCE Res0 ON PLC
        TASK MainTask(INTERVAL := T#20ms, PRIORITY := 0);
        PROGRAM MainInstance WITH MainTask : Main;
    END_RESOURCE
END_CONFIGURATION
