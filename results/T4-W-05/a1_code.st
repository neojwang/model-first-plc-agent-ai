FUNCTION_BLOCK LevelControlRuntime
VAR_INPUT
    StartSignal : BOOL;
    StopSignal : BOOL;
    LevelValue : INT;
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
    ErrorValue : REAL;
    PreviousError : REAL := 0.0;
    IntegralTerm : REAL := 0.0;
    CandidateIntegral : REAL;
    DerivativeTerm : REAL;
    RawDemand : REAL;
    CandidateDemand : REAL;
    BoundedDemand : REAL;
    PidInitialized : BOOL := FALSE;
END_VAR

(* Region encoding: 0 = LOW, 1 = MID, 2 = HIGH. *)
StartEdge(CLK := StartSignal);
start := StartEdge.Q;
stop := StopSignal;

h := INT_TO_REAL(LevelValue) * h_span / INT_TO_REAL(ScaleValue);
ErrorValue := h_sp - h;

IF h < h_target THEN
    r := 0;
ELSIF h < h_max THEN
    r := 1;
ELSE
    r := 2;
END_IF;

(* The hold condition measures continuous time in tolerance in x1. *)
HoldTimer(
    IN := x1 AND NOT stop AND (ABS(ErrorValue) <= eps),
    PT := t_h
);
settled := HoldTimer.Q;

(* Evaluate transitions from the current situation only. *)
IF x0 THEN
    IF start AND NOT stop AND ((r = 0) OR (r = 1)) THEN
        x0 := FALSE;
        x1 := TRUE;
    END_IF;
ELSIF x1 THEN
    IF stop OR settled OR (r = 2) THEN
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
    (* Positional PID; demand is expressed as percent valve opening.
       Kp has units percent per level unit; Ti and Td are in seconds. *)
    IF NOT PidInitialized THEN
        PreviousError := ErrorValue;
        IntegralTerm := 0.0;
        PidInitialized := TRUE;
    END_IF;

    DerivativeTerm := 0.0;
    IF CycleSeconds > 0.0 THEN
        DerivativeTerm :=
            Kp * Td * (ErrorValue - PreviousError) / CycleSeconds;
    END_IF;

    RawDemand := Kp * ErrorValue + IntegralTerm + DerivativeTerm;

    (* Suspend integration whenever the current demand is clamped.
       Also reject an integral increment that would cause clamping. *)
    IF (RawDemand >= 0.0) AND (RawDemand <= 100.0)
       AND (Ti > 0.0) AND (CycleSeconds > 0.0) THEN
        CandidateIntegral :=
            IntegralTerm + Kp * ErrorValue * CycleSeconds / Ti;
        CandidateDemand :=
            Kp * ErrorValue + CandidateIntegral + DerivativeTerm;

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

    PreviousError := ErrorValue;
ELSE
    IntegralTerm := 0.0;
    PreviousError := ErrorValue;
    PidInitialized := FALSE;
    BoundedDemand := 0.0;
    settled := FALSE;
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

    h_span : REAL := 10.0;
    h_sp : REAL;
    h_target : REAL;
    h_max : REAL;
    eps : REAL;
    t_h : TIME := T#10s;

    (* Initial tuning values; adjust for the simulated plant. *)
    Kp : REAL := 20.0;
    Ti : REAL := 5.0;
    Td : REAL := 0.0;

    (* Must match the configured periodic task interval. *)
    CycleSeconds : REAL := 0.02;
END_VAR

h_sp := 0.8 * h_span;
h_target := h_sp;
h_max := 0.9 * h_span;
eps := 0.02 * h_span;

Controller(
    StartSignal := StartCommand,
    StopSignal := StopCommand,
    LevelValue := LevelMeter,
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


CONFIGURATION Config0
    RESOURCE Res0 ON PLC
        TASK ControlTask(INTERVAL := T#20ms, PRIORITY := 0);
        PROGRAM MainInstance WITH ControlTask : Main;
    END_RESOURCE
END_CONFIGURATION
