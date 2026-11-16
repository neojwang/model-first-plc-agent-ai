FUNCTION_BLOCK LevelControlRuntime
VAR_INPUT
    StartSignal : BOOL;
    StopSignal : BOOL;
    LevelSignal : INT;
    ScaleValue : INT;
    h_span : REAL;
    Kp : REAL;
    Ti : REAL;
    Td : REAL;
    CycleSeconds : REAL;
    t_h : TIME;
END_VAR
VAR_OUTPUT
    FillDemand : INT;
    DischargeDemand : INT;
    fill_valve : BOOL;
    discharge_valve : BOOL;
END_VAR
VAR CONSTANT
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

    x0 : BOOL := TRUE;
    x1 : BOOL := FALSE;

    h : REAL;
    h_sp : REAL;
    h_target : REAL;
    h_max : REAL;
    eps : REAL;
    LevelError : REAL;

    IntegralTerm : REAL := 0.0;
    PreviousError : REAL := 0.0;
    DerivativeTerm : REAL;
    ProportionalTerm : REAL;
    RawDemand : REAL;
    BoundedDemand : REAL;
    CandidateIntegral : REAL;
    CandidateDemand : REAL;
    WasRegulating : BOOL;
END_VAR

StartEdge(CLK := StartSignal);
start := StartEdge.Q;
stop := StopSignal;

h := INT_TO_REAL(LevelSignal) * h_span / INT_TO_REAL(ScaleValue);
h_sp := 0.8 * h_span;
h_target := h_sp;
h_max := 0.9 * h_span;
eps := 0.02 * h_span;
LevelError := h_sp - h;

IF h < h_target THEN
    r := REGION_LOW;
ELSIF h < h_max THEN
    r := REGION_MIDDLE;
ELSE
    r := REGION_HIGH;
END_IF;

WasRegulating := x1;

(* The timer measures uninterrupted time in tolerance during step x1. *)
HoldTimer(
    IN := x1 AND NOT stop AND (ABS(LevelError) <= eps),
    PT := t_h
);
settled := HoldTimer.Q;

(* Evaluate transitions from the situation at the beginning of the scan. *)
IF x0 THEN
    IF start AND NOT stop AND (r <> REGION_HIGH) THEN
        x0 := FALSE;
        x1 := TRUE;
    END_IF;
ELSIF x1 THEN
    IF stop OR settled OR (r = REGION_HIGH) THEN
        x1 := FALSE;
        x0 := TRUE;
    END_IF;
ELSE
    x0 := TRUE;
    x1 := FALSE;
END_IF;

(* Explicit stop priority, including the initial situation. *)
IF stop THEN
    x0 := TRUE;
    x1 := FALSE;
END_IF;

fill_valve := x1;
discharge_valve := x1;

FillDemand := 0;
DischargeDemand := 0;

IF x1 THEN
    IF NOT WasRegulating THEN
        IntegralTerm := 0.0;
        PreviousError := LevelError;
    END_IF;

    ProportionalTerm := Kp * LevelError;
    DerivativeTerm := 0.0;

    IF (CycleSeconds > 0.0) AND (Td > 0.0) THEN
        DerivativeTerm :=
            Kp * Td * (LevelError - PreviousError) / CycleSeconds;
    END_IF;

    RawDemand := ProportionalTerm + IntegralTerm + DerivativeTerm;

    (* Hold the integral whenever the output is clamped.
       Reject an integral increment that would cause clamping. *)
    IF (RawDemand >= 0.0) AND (RawDemand <= 100.0) THEN
        IF (Ti > 0.0) AND (CycleSeconds > 0.0) THEN
            CandidateIntegral :=
                IntegralTerm + Kp * LevelError * CycleSeconds / Ti;
            CandidateDemand :=
                ProportionalTerm + CandidateIntegral + DerivativeTerm;

            IF (CandidateDemand >= 0.0) AND
               (CandidateDemand <= 100.0) THEN
                IntegralTerm := CandidateIntegral;
                RawDemand := CandidateDemand;
            END_IF;
        END_IF;
    END_IF;

    IF RawDemand < 0.0 THEN
        BoundedDemand := 0.0;
    ELSIF RawDemand > 100.0 THEN
        BoundedDemand := 100.0;
    ELSE
        BoundedDemand := RawDemand;
    END_IF;

    FillDemand :=
        REAL_TO_INT(BoundedDemand * INT_TO_REAL(ScaleValue) / 100.0);
    DischargeDemand :=
        REAL_TO_INT(0.4 * INT_TO_REAL(ScaleValue));

    PreviousError := LevelError;
ELSE
    IntegralTerm := 0.0;
    PreviousError := LevelError;
    DerivativeTerm := 0.0;
    RawDemand := 0.0;
    BoundedDemand := 0.0;

    (* Clear owned timing state immediately on leaving regulation. *)
    HoldTimer(IN := FALSE, PT := t_h);
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
VAR CONSTANT
    FULL_SCALE : INT := 1000;
END_VAR
VAR
    Controller : LevelControlRuntime;

    h_span : REAL := 10.0;
    t_h : TIME := T#10s;

    (* Commissioning parameters; tune for the plant.
       Kp uses percent opening per volt, Ti and Td use seconds. *)
    Kp : REAL := 100.0;
    Ti : REAL := 5.0;
    Td : REAL := 0.0;

    (* Schedule Main periodically at 20 ms in the OpenPLC task. *)
    CycleSeconds : REAL := 0.02;
END_VAR

Controller(
    StartSignal := StartCommand,
    StopSignal := StopCommand,
    LevelSignal := LevelMeter,
    ScaleValue := FULL_SCALE,
    h_span := h_span,
    Kp := Kp,
    Ti := Ti,
    Td := Td,
    CycleSeconds := CycleSeconds,
    t_h := t_h
);

FillValve := Controller.FillDemand;
DischargeValve := Controller.DischargeDemand;

END_PROGRAM
