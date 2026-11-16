FUNCTION_BLOCK LevelControlRuntime
VAR_INPUT
    StartInput : BOOL;
    StopInput : BOOL;
    LevelInput : INT;
    FullScaleValue : INT;
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

    x0 : BOOL := TRUE;
    x1 : BOOL := FALSE;
    start : BOOL := FALSE;
    stop : BOOL := FALSE;
    settled : BOOL := FALSE;

    (* Region encoding: 0 = LOW, 1 = MID, 2 = HIGH. *)
    r : INT := 0;

    h : REAL := 0.0;
    LevelError : REAL := 0.0;
    NormalizedError : REAL := 0.0;
    PreviousError : REAL := 0.0;
    ProportionalTerm : REAL := 0.0;
    IntegralTerm : REAL := 0.0;
    IntegralIncrement : REAL := 0.0;
    DerivativeTerm : REAL := 0.0;
    CandidateDemand : REAL := 0.0;
    RawDemand : REAL := 0.0;
    BoundedDemand : REAL := 0.0;
    EnteringRegulation : BOOL := FALSE;
END_VAR

StartEdge(CLK := StartInput);
start := StartEdge.Q;
stop := StopInput;

h := INT_TO_REAL(LevelInput) * h_span / INT_TO_REAL(FullScaleValue);
LevelError := h_sp - h;
NormalizedError := LevelError / h_span;

IF h < h_target THEN
    r := 0;
ELSIF h < h_max THEN
    r := 1;
ELSE
    r := 2;
END_IF;

(* The timer measures uninterrupted time inside the tolerance band,
   exclusively while the regulation step is active. *)
HoldTimer(
    IN := x1 AND (ABS(LevelError) <= eps) AND NOT stop,
    PT := t_h
);
settled := x1 AND HoldTimer.Q;

EnteringRegulation := FALSE;

(* Evaluate transitions from the current GRAFCET situation. *)
IF x0 THEN
    IF start AND NOT stop AND (r <> 2) THEN
        x0 := FALSE;
        x1 := TRUE;
        EnteringRegulation := TRUE;
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

(* Continuous, nonstored step actions. *)
FillCommand := 0;
DischargeCommand := 0;

IF fill_valve THEN
    (* Restart policy: clear the integral and initialize derivative history
       on each activation. PID demand is expressed as a fraction of full scale.
       Kp therefore acts on the level error normalized by h_span. *)
    IF EnteringRegulation THEN
        IntegralTerm := 0.0;
        PreviousError := NormalizedError;
    END_IF;

    ProportionalTerm := Kp * NormalizedError;

    DerivativeTerm := 0.0;
    IF CycleSeconds > 0.0 THEN
        DerivativeTerm :=
            Kp * Td * (NormalizedError - PreviousError) / CycleSeconds;
    END_IF;

    RawDemand := ProportionalTerm + IntegralTerm + DerivativeTerm;
    IntegralIncrement := 0.0;

    (* Freeze integration whenever the current output requires clamping.
       Also reject any integral update that would itself require clamping. *)
    IF (RawDemand >= 0.0) AND (RawDemand <= 1.0) THEN
        IF (Ti > 0.0) AND (CycleSeconds > 0.0) THEN
            IntegralIncrement := Kp * NormalizedError * CycleSeconds / Ti;
            CandidateDemand := RawDemand + IntegralIncrement;

            IF (CandidateDemand >= 0.0) AND (CandidateDemand <= 1.0) THEN
                IntegralTerm := IntegralTerm + IntegralIncrement;
                RawDemand := CandidateDemand;
            END_IF;
        END_IF;
    END_IF;

    IF RawDemand > 1.0 THEN
        BoundedDemand := 1.0;
    ELSIF RawDemand < 0.0 THEN
        BoundedDemand := 0.0;
    ELSE
        BoundedDemand := RawDemand;
    END_IF;

    PreviousError := NormalizedError;

    FillCommand :=
        REAL_TO_INT(BoundedDemand * INT_TO_REAL(FullScaleValue));
ELSE
    BoundedDemand := 0.0;
    settled := FALSE;
END_IF;

IF discharge_valve THEN
    DischargeCommand := REAL_TO_INT(0.4 * INT_TO_REAL(FullScaleValue));
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
    h_sp : REAL := 8.0;
    h_target : REAL := 8.0;
    h_max : REAL := 9.0;
    eps : REAL := 0.2;
    t_h : TIME := T#10s;

    (* Initial tuning values; adjust for the simulated plant. *)
    Kp : REAL := 1.0;
    Ti : REAL := 10.0;
    Td : REAL := 0.0;

    (* Must match the configured cyclic task interval below. *)
    CycleSeconds : REAL := 0.02;
END_VAR

Controller(
    StartInput := StartCommand,
    StopInput := StopCommand,
    LevelInput := LevelMeter,
    FullScaleValue := FULL_SCALE,
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
