FUNCTION_BLOCK LevelControlRuntime
VAR_INPUT
    StartSignal : BOOL;
    StopSignal : BOOL;
    LevelSample : INT;
    FullScaleValue : INT;
    h_span : REAL;
    Kp : REAL;
    Ti : REAL;
    Td : REAL;
    t_h : TIME;
    CycleSeconds : REAL;
END_VAR
VAR_OUTPUT
    FillCommand : INT;
    DischargeCommand : INT;
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
    r : INT := 0;

    x0 : BOOL := TRUE;
    x1 : BOOL := FALSE;
    WasRegulating : BOOL;

    h : REAL;
    h_sp : REAL;
    h_target : REAL;
    h_max : REAL;
    eps : REAL;
    LevelError : REAL;
    PreviousError : REAL := 0.0;

    ProportionalTerm : REAL;
    IntegralTerm : REAL := 0.0;
    DerivativeTerm : REAL;
    CandidateIntegral : REAL;
    UnconstrainedDemand : REAL;
    CandidateDemand : REAL;
    LimitedDemand : REAL;
END_VAR

StartEdge(CLK := StartSignal);
start := StartEdge.Q;
stop := StopSignal;

h_sp := 0.8 * h_span;
h_target := h_sp;
h_max := 0.9 * h_span;
eps := 0.02 * h_span;

h := INT_TO_REAL(LevelSample) * h_span / INT_TO_REAL(FullScaleValue);
LevelError := h_sp - h;

IF h < h_target THEN
    r := REGION_LOW;
ELSIF h < h_max THEN
    r := REGION_MIDDLE;
ELSE
    r := REGION_HIGH;
END_IF;

WasRegulating := x1;

(* The hold condition measures continuous time inside the tolerance
   band while x1 is active, not merely the duration of x1. *)
HoldTimer(
    IN := x1 AND NOT stop AND (ABS(LevelError) <= eps),
    PT := t_h
);
settled := HoldTimer.Q;

(* Evaluate transitions using the situation at the start of this scan. *)
IF x0 THEN
    IF start AND NOT stop AND NOT (r = REGION_HIGH) THEN
        x0 := FALSE;
        x1 := TRUE;
    END_IF;
ELSIF x1 THEN
    IF stop OR settled OR (r = REGION_HIGH) THEN
        x1 := FALSE;
        x0 := TRUE;
    END_IF;
END_IF;

(* Clear the owned hold condition immediately upon leaving x1. *)
IF NOT x1 THEN
    HoldTimer(IN := FALSE, PT := t_h);
    settled := FALSE;
END_IF;

fill_valve := x1;
discharge_valve := x1;

FillCommand := 0;
DischargeCommand := 0;
LimitedDemand := 0.0;

(* PID demand is expressed as a fraction of full valve opening.
   Kp therefore has units of opening fraction per level unit.
   Ti, Td, and CycleSeconds are expressed in seconds. *)
IF x1 THEN
    IF NOT WasRegulating THEN
        PreviousError := LevelError;
    END_IF;

    ProportionalTerm := Kp * LevelError;
    DerivativeTerm := 0.0;

    IF (Td > 0.0) AND (CycleSeconds > 0.0) THEN
        DerivativeTerm :=
            Kp * Td * (LevelError - PreviousError) / CycleSeconds;
    END_IF;

    UnconstrainedDemand :=
        ProportionalTerm + IntegralTerm + DerivativeTerm;

    (* Suspend integration whenever the current output is clamped.
       Also reject an integral update that would cause clamping. *)
    IF (Ti > 0.0) AND (CycleSeconds > 0.0) THEN
        IF (UnconstrainedDemand >= 0.0) AND
           (UnconstrainedDemand <= 1.0) THEN
            CandidateIntegral :=
                IntegralTerm + Kp * LevelError * CycleSeconds / Ti;
            CandidateDemand :=
                ProportionalTerm + CandidateIntegral + DerivativeTerm;

            IF (CandidateDemand >= 0.0) AND
               (CandidateDemand <= 1.0) THEN
                IntegralTerm := CandidateIntegral;
            END_IF;
        END_IF;
    END_IF;

    UnconstrainedDemand :=
        ProportionalTerm + IntegralTerm + DerivativeTerm;

    IF UnconstrainedDemand < 0.0 THEN
        LimitedDemand := 0.0;
    ELSIF UnconstrainedDemand > 1.0 THEN
        LimitedDemand := 1.0;
    ELSE
        LimitedDemand := UnconstrainedDemand;
    END_IF;

    FillCommand :=
        REAL_TO_INT(LimitedDemand * INT_TO_REAL(FullScaleValue));
    DischargeCommand :=
        REAL_TO_INT(0.4 * INT_TO_REAL(FullScaleValue));
END_IF;

(* IntegralTerm is retained, but never integrated, outside x1. *)
PreviousError := LevelError;

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
    ScanSeconds : REAL := 0.02;
END_VAR
VAR
    Controller : LevelControlRuntime;

    h_span : REAL := 10.0;
    t_h : TIME := T#10s;

    (* Initial tuning values; commission for the simulated plant. *)
    Kp : REAL := 1.0;
    Ti : REAL := 10.0;
    Td : REAL := 0.0;
END_VAR

Controller(
    StartSignal := StartCommand,
    StopSignal := StopCommand,
    LevelSample := LevelMeter,
    FullScaleValue := FULL_SCALE,
    h_span := h_span,
    Kp := Kp,
    Ti := Ti,
    Td := Td,
    t_h := t_h,
    CycleSeconds := ScanSeconds
);

FillValve := Controller.FillCommand;
DischargeValve := Controller.DischargeCommand;

END_PROGRAM


CONFIGURATION Config0
    RESOURCE Res0 ON PLC
        TASK ControlTask(INTERVAL := T#20ms, PRIORITY := 0);
        PROGRAM MainInstance WITH ControlTask : Main;
    END_RESOURCE
END_CONFIGURATION
