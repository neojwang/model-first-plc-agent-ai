FUNCTION_BLOCK LevelControlRuntime
VAR_INPUT
    StartSignal : BOOL;
    StopSignal : BOOL;
    LevelValue : INT;
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
    CyclePeriod : TIME;
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
    (* Region encoding: 0 = LOW, 1 = MID, 2 = HIGH. *)
    r : INT;

    x0 : BOOL := TRUE;
    x1 : BOOL := FALSE;
    PreviousRegulation : BOOL := FALSE;

    h : REAL;
    e : REAL;
    PreviousError : REAL := 0.0;
    SecondsPerCycle : REAL;
    ProportionalTerm : REAL;
    IntegralTerm : REAL := 0.0;
    DerivativeTerm : REAL;
    TrialIntegral : REAL;
    UnboundedDemand : REAL;
    BoundedDemand : REAL;
END_VAR

StartEdge(CLK := StartSignal);
start := StartEdge.Q;
stop := StopSignal;

h := INT_TO_REAL(LevelValue) * h_span / INT_TO_REAL(FullScaleValue);
e := h_sp - h;

IF h < h_target THEN
    r := 0;
ELSIF h < h_max THEN
    r := 1;
ELSE
    r := 2;
END_IF;

(* The hold condition is nonretentive and belongs only to x1.
   Calling before the transition evaluation keeps it FALSE on entry. *)
HoldTimer(
    IN := x1 AND NOT stop AND (ABS(e) <= eps),
    PT := t_h
);
settled := HoldTimer.Q;

(* Evaluate transitions using the current situation, without cascading. *)
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
ELSE
    x0 := TRUE;
    x1 := FALSE;
END_IF;

fill_valve := x1;
discharge_valve := x1;

FillCommand := 0;
DischargeCommand := 0;

SecondsPerCycle := TIME_TO_REAL(CyclePeriod) / 1000.0;

IF fill_valve THEN
    IF NOT PreviousRegulation THEN
        IntegralTerm := 0.0;
        PreviousError := e;
    END_IF;

    ProportionalTerm := Kp * e;
    DerivativeTerm := 0.0;

    IF (Td > 0.0) AND (SecondsPerCycle > 0.0) THEN
        DerivativeTerm :=
            Kp * Td * (e - PreviousError) / SecondsPerCycle;
    END_IF;

    UnboundedDemand :=
        ProportionalTerm + IntegralTerm + DerivativeTerm;

    (* Suspend integration whenever the output is clamped.
       Also reject an integration increment that would cause clamping. *)
    IF (Ti > 0.0) AND (SecondsPerCycle > 0.0)
       AND (UnboundedDemand >= 0.0)
       AND (UnboundedDemand <= 100.0) THEN
        TrialIntegral :=
            IntegralTerm + Kp * e * SecondsPerCycle / Ti;

        IF ((ProportionalTerm + TrialIntegral + DerivativeTerm) >= 0.0)
           AND ((ProportionalTerm + TrialIntegral + DerivativeTerm) <= 100.0) THEN
            IntegralTerm := TrialIntegral;
        END_IF;
    END_IF;

    UnboundedDemand :=
        ProportionalTerm + IntegralTerm + DerivativeTerm;

    IF UnboundedDemand < 0.0 THEN
        BoundedDemand := 0.0;
    ELSIF UnboundedDemand > 100.0 THEN
        BoundedDemand := 100.0;
    ELSE
        BoundedDemand := UnboundedDemand;
    END_IF;

    FillCommand := REAL_TO_INT(
        BoundedDemand * INT_TO_REAL(FullScaleValue) / 100.0
    );

    PreviousError := e;
ELSE
    IntegralTerm := 0.0;
    PreviousError := e;
    BoundedDemand := 0.0;
END_IF;

IF discharge_valve THEN
    DischargeCommand :=
        REAL_TO_INT(0.4 * INT_TO_REAL(FullScaleValue));
END_IF;

PreviousRegulation := x1;

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

    (* Initial tuning values; commission these for the actual plant.
       PID output units are percent; error units are volts. *)
    Kp : REAL := 50.0;
    Ti : REAL := 10.0;
    Td : REAL := 0.0;

    (* Configure the OpenPLC cyclic task to this same period. *)
    CyclePeriod : TIME := T#20ms;
END_VAR

h_sp := 0.8 * h_span;
h_target := h_sp;
h_max := 0.9 * h_span;
eps := 0.02 * h_span;

Controller(
    StartSignal := StartCommand,
    StopSignal := StopCommand,
    LevelValue := LevelMeter,
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
    CyclePeriod := CyclePeriod
);

FillValve := Controller.FillCommand;
DischargeValve := Controller.DischargeCommand;

END_PROGRAM
