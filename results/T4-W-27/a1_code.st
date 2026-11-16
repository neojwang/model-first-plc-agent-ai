FUNCTION_BLOCK LevelControlRuntime
VAR_INPUT
    StartSignal : BOOL;
    StopSignal : BOOL;
    LevelRaw : INT;
    FullScaleValue : INT;
    h_span : REAL;
    h_sp : REAL;
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

    (* Region encoding: 0 = LOW, 1 = MID, 2 = HIGH. *)
    r : INT;

    x0 : BOOL := TRUE;
    x1 : BOOL := FALSE;
    WasRegulating : BOOL := FALSE;

    h : REAL;
    ErrorValue : REAL;
    PreviousError : REAL := 0.0;

    ProportionalTerm : REAL;
    IntegralTerm : REAL := 0.0;
    DerivativeTerm : REAL;
    IntegralCandidate : REAL;
    CandidateDemand : REAL;
    UnboundedDemand : REAL;
    BoundedDemand : REAL;
END_VAR

StartEdge(CLK := StartSignal);
start := StartEdge.Q;
stop := StopSignal;

h := INT_TO_REAL(LevelRaw) * h_span / INT_TO_REAL(FullScaleValue);
ErrorValue := h_sp - h;

IF h < h_sp THEN
    r := 0;
ELSIF h < h_max THEN
    r := 1;
ELSE
    r := 2;
END_IF;

(* The hold interval is continuous and belongs only to x1. *)
HoldTimer(
    IN := x1 AND (ABS(ErrorValue) <= eps) AND NOT stop,
    PT := t_h
);
settled := HoldTimer.Q;

(* Evaluate transitions using the situation at the start of the scan. *)
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

FillCommand := 0;
DischargeCommand := 0;

IF x1 THEN
    (* Restart policy: reset the integral and suppress derivative kick. *)
    IF NOT WasRegulating THEN
        IntegralTerm := 0.0;
        PreviousError := ErrorValue;
    END_IF;

    (* Parallel PID; its demand is expressed as percent valve opening.
       Kp therefore has units of percent per unit of measured level. *)
    ProportionalTerm := Kp * ErrorValue;
    DerivativeTerm := 0.0;

    IF CycleSeconds > 0.0 THEN
        DerivativeTerm :=
            Kp * Td * (ErrorValue - PreviousError) / CycleSeconds;
    END_IF;

    UnboundedDemand := ProportionalTerm + IntegralTerm + DerivativeTerm;

    (* Freeze integration whenever the current output is clamped.
       Also reject an integration increment that would cause clamping. *)
    IF (UnboundedDemand >= 0.0) AND
       (UnboundedDemand <= 100.0) AND
       (Ti > 0.0) AND
       (CycleSeconds > 0.0) THEN

        IntegralCandidate :=
            IntegralTerm + Kp * ErrorValue * CycleSeconds / Ti;

        CandidateDemand :=
            ProportionalTerm + IntegralCandidate + DerivativeTerm;

        IF (CandidateDemand >= 0.0) AND
           (CandidateDemand <= 100.0) THEN
            IntegralTerm := IntegralCandidate;
            UnboundedDemand := CandidateDemand;
        END_IF;
    END_IF;

    IF UnboundedDemand < 0.0 THEN
        BoundedDemand := 0.0;
    ELSIF UnboundedDemand > 100.0 THEN
        BoundedDemand := 100.0;
    ELSE
        BoundedDemand := UnboundedDemand;
    END_IF;

    FillCommand :=
        REAL_TO_INT(BoundedDemand * INT_TO_REAL(FullScaleValue) / 100.0);
    DischargeCommand :=
        REAL_TO_INT(0.4 * INT_TO_REAL(FullScaleValue));

    PreviousError := ErrorValue;
END_IF;

WasRegulating := x1;

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
    h_max : REAL := 9.0;
    eps : REAL := 0.2;
    t_h : TIME := T#10s;
    CycleSeconds : REAL := 0.02;
END_VAR
VAR
    Controller : LevelControlRuntime;

    (* Initial tuning values; adjust for the simulated plant. *)
    Kp : REAL := 20.0;
    Ti : REAL := 10.0;
    Td : REAL := 0.0;
END_VAR

Controller(
    StartSignal := StartCommand,
    StopSignal := StopCommand,
    LevelRaw := LevelMeter,
    FullScaleValue := FULL_SCALE,
    h_span := h_span,
    h_sp := h_sp,
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
