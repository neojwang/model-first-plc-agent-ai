FUNCTION_BLOCK LevelControlRuntime
VAR_INPUT
    StartButton : BOOL;
    StopButton : BOOL;
    LevelRaw : INT;
    FullScaleValue : INT;
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
    fill_valve : BOOL;
    discharge_valve : BOOL;
    FillCommand : INT;
    DischargeCommand : INT;
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
    EnteringRegulation : BOOL;

    h : REAL;
    ErrorValue : REAL;
    PreviousError : REAL := 0.0;
    ProportionalTerm : REAL;
    IntegralTerm : REAL := 0.0;
    IntegralCandidate : REAL;
    DerivativeTerm : REAL;
    UnclampedDemand : REAL;
    BoundedDemand : REAL;
END_VAR
VAR CONSTANT
    REGION_LOW : INT := 0;
    REGION_MIDDLE : INT := 1;
    REGION_HIGH : INT := 2;
END_VAR

StartEdge(CLK := StartButton);
start := StartEdge.Q;
stop := StopButton;

h := INT_TO_REAL(LevelRaw) / INT_TO_REAL(FullScaleValue);
ErrorValue := h_sp - h;

IF h < h_target THEN
    r := REGION_LOW;
ELSIF h < h_max THEN
    r := REGION_MIDDLE;
ELSE
    r := REGION_HIGH;
END_IF;

(* The hold condition is continuous and belongs only to x1. *)
HoldTimer(
    IN := x1 AND (ABS(ErrorValue) <= eps) AND NOT stop,
    PT := t_h
);
settled := x1 AND HoldTimer.Q;

EnteringRegulation := FALSE;

(* Evaluate transitions against the situation at scan entry. *)
IF x0 THEN
    IF start AND NOT stop AND (r <> REGION_HIGH) THEN
        x0 := FALSE;
        x1 := TRUE;
        EnteringRegulation := TRUE;
    END_IF;
ELSIF x1 THEN
    IF stop OR settled OR (r = REGION_HIGH) THEN
        x1 := FALSE;
        x0 := TRUE;
        settled := FALSE;
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
    IF EnteringRegulation THEN
        IntegralTerm := 0.0;
        PreviousError := ErrorValue;
    END_IF;

    ProportionalTerm := Kp * ErrorValue;
    DerivativeTerm := 0.0;

    IF (CycleSeconds > 0.0) AND (Td > 0.0) THEN
        DerivativeTerm :=
            Kp * Td * (ErrorValue - PreviousError) / CycleSeconds;
    END_IF;

    (* Demand is expressed as a fraction of full valve opening. *)
    UnclampedDemand :=
        ProportionalTerm + IntegralTerm + DerivativeTerm;

    (* Suspend integration whenever the current demand is clamped.
       Also reject an integral increment that would cause clamping. *)
    IF (UnclampedDemand >= 0.0)
       AND (UnclampedDemand <= 1.0)
       AND (Ti > 0.0)
       AND (CycleSeconds > 0.0) THEN

        IntegralCandidate :=
            IntegralTerm + Kp * ErrorValue * CycleSeconds / Ti;

        UnclampedDemand :=
            ProportionalTerm + IntegralCandidate + DerivativeTerm;

        IF (UnclampedDemand >= 0.0)
           AND (UnclampedDemand <= 1.0) THEN
            IntegralTerm := IntegralCandidate;
        END_IF;
    END_IF;

    IF UnclampedDemand > 1.0 THEN
        BoundedDemand := 1.0;
    ELSIF UnclampedDemand < 0.0 THEN
        BoundedDemand := 0.0;
    ELSE
        BoundedDemand := UnclampedDemand;
    END_IF;

    FillCommand :=
        REAL_TO_INT(BoundedDemand * INT_TO_REAL(FullScaleValue));
    PreviousError := ErrorValue;
ELSE
    IntegralTerm := 0.0;
    PreviousError := ErrorValue;
    BoundedDemand := 0.0;
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

    (* Normalized level parameters: 1.0 corresponds to 10 V. *)
    h_sp : REAL := 0.8;
    h_target : REAL := 0.8;
    h_max : REAL := 0.9;
    eps : REAL := 0.02;
    t_h : TIME := T#10s;

    (* Commission these gains for the plant; Ti and Td are in seconds. *)
    Kp : REAL := 1.0;
    Ti : REAL := 10.0;
    Td : REAL := 0.0;

    (* Schedule Main periodically at 20 ms.
       Change this value if the configured task period changes. *)
    CycleSeconds : REAL := 0.02;
END_VAR

Controller(
    StartButton := StartCommand,
    StopButton := StopCommand,
    LevelRaw := LevelMeter,
    FullScaleValue := FULL_SCALE,
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
