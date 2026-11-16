FUNCTION_BLOCK LevelControlRuntime
VAR_INPUT
    StartSignal : BOOL;
    StopSignal : BOOL;
    LevelSignal : INT;
    ScaleValue : INT;
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
    FillCommand : INT;
    DischargeCommand : INT;
    fill_valve : BOOL;
    discharge_valve : BOOL;
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
    e : REAL;
    PreviousError : REAL := 0.0;
    IntegralTerm : REAL := 0.0;
    ProportionalTerm : REAL;
    DerivativeTerm : REAL;
    CandidateIntegral : REAL;
    CandidateDemand : REAL;
    RawDemand : REAL;
    BoundedDemand : REAL;
    PidWasActive : BOOL := FALSE;
END_VAR
VAR CONSTANT
    REGION_LOW : INT := 0;
    REGION_MIDDLE : INT := 1;
    REGION_HIGH : INT := 2;
END_VAR

StartEdge(CLK := StartSignal);
start := StartEdge.Q;
stop := StopSignal;

h := INT_TO_REAL(LevelSignal) * h_span / INT_TO_REAL(ScaleValue);
e := h_sp - h;

IF h < h_target THEN
    r := REGION_LOW;
ELSIF h < h_max THEN
    r := REGION_MIDDLE;
ELSE
    r := REGION_HIGH;
END_IF;

(* The dwell time measures continuous tolerance satisfaction in x1. *)
HoldTimer(
    IN := x1 AND NOT stop AND (ABS(e) <= eps),
    PT := t_h
);
settled := HoldTimer.Q;

(* Evaluate transitions from the current situation exactly once per scan. *)
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

fill_valve := x1;
discharge_valve := x1;

FillCommand := 0;
DischargeCommand := 0;

IF fill_valve THEN
    (* Parallel PID:
       Kp is percent opening per level unit;
       Ti and Td are expressed in seconds. *)
    ProportionalTerm := Kp * e;
    DerivativeTerm := 0.0;

    IF PidWasActive AND (CycleSeconds > 0.0) THEN
        DerivativeTerm :=
            Kp * Td * (e - PreviousError) / CycleSeconds;
    END_IF;

    RawDemand := ProportionalTerm + IntegralTerm + DerivativeTerm;

    (* Freeze the integral while the demand is clamped.
       Reject an integral update that would itself cause clamping. *)
    IF (RawDemand >= 0.0) AND (RawDemand <= 100.0)
       AND (Ti > 0.0) AND (CycleSeconds > 0.0) THEN

        CandidateIntegral :=
            IntegralTerm + Kp * e * CycleSeconds / Ti;
        CandidateDemand :=
            ProportionalTerm + CandidateIntegral + DerivativeTerm;

        IF (CandidateDemand >= 0.0) AND (CandidateDemand <= 100.0) THEN
            IntegralTerm := CandidateIntegral;
            RawDemand := CandidateDemand;
        END_IF;
    END_IF;

    IF RawDemand < 0.0 THEN
        BoundedDemand := 0.0;
    ELSIF RawDemand > 100.0 THEN
        BoundedDemand := 100.0;
    ELSE
        BoundedDemand := RawDemand;
    END_IF;

    FillCommand :=
        REAL_TO_INT(BoundedDemand * INT_TO_REAL(ScaleValue) / 100.0);

    PreviousError := e;
    PidWasActive := TRUE;
ELSE
    IntegralTerm := 0.0;
    PreviousError := e;
    PidWasActive := FALSE;
END_IF;

IF discharge_valve THEN
    DischargeCommand := REAL_TO_INT(0.4 * INT_TO_REAL(ScaleValue));
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
    Initialized : BOOL := FALSE;

    h_span : REAL := 10.0;
    h_sp : REAL;
    h_target : REAL;
    h_max : REAL;
    eps : REAL;
    t_h : TIME := T#10s;

    (* Initial tuning values; commission for the actual plant. *)
    Kp : REAL := 20.0;
    Ti : REAL := 10.0;
    Td : REAL := 0.0;

    (* Configure the Main cyclic task for 20 ms.
       Update this value if the configured task period changes. *)
    CycleSeconds : REAL := 0.02;
END_VAR

IF NOT Initialized THEN
    FillValve := 0;
    DischargeValve := 0;
    Initialized := TRUE;
END_IF;

h_sp := 0.8 * h_span;
h_target := h_sp;
h_max := 0.9 * h_span;
eps := 0.02 * h_span;

Controller(
    StartSignal := StartCommand,
    StopSignal := StopCommand,
    LevelSignal := LevelMeter,
    ScaleValue := FULL_SCALE,
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

FillValve := Controller.FillCommand;
DischargeValve := Controller.DischargeCommand;

END_PROGRAM
