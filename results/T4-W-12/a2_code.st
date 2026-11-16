FUNCTION_BLOCK TankLevelController
VAR_INPUT
    StartCommand : BOOL;
    StopCommand : BOOL;
    LevelMeter : INT;
    Kp : REAL := 10.0;
    Ti : REAL := 10.0;
    Td : REAL := 0.0;
    CycleSeconds : REAL := 0.02;
    h_span : REAL := 10.0;
    t_h : TIME := T#10s;
END_VAR
VAR_OUTPUT
    FillValve : INT;
    DischargeValve : INT;
    fill_valve : BOOL;
    discharge_valve : BOOL;
END_VAR
VAR CONSTANT
    FULL_SCALE : INT := 1000;
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

    ActiveStep : INT := 0;
    x0 : BOOL;
    x1 : BOOL;

    h : REAL;
    h_sp : REAL;
    h_target : REAL;
    h_max : REAL;
    eps : REAL;
    LevelError : REAL;

    ProportionalTerm : REAL;
    IntegralTerm : REAL := 0.0;
    IntegralCandidate : REAL;
    DerivativeTerm : REAL;
    PreviousError : REAL := 0.0;
    DerivativeReady : BOOL := FALSE;
    UnboundedDemand : REAL;
    CandidateDemand : REAL;
    BoundedDemand : REAL;
    IntegrationEnabled : BOOL;
END_VAR

StartEdge(CLK := StartCommand);
start := StartEdge.Q;
stop := StopCommand;

h := INT_TO_REAL(LevelMeter) * h_span / INT_TO_REAL(FULL_SCALE);
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

(* The hold interval is continuous and belongs to the regulation step. *)
HoldTimer(
    IN := (ActiveStep = 1)
          AND NOT stop
          AND (ABS(LevelError) <= eps),
    PT := t_h
);
settled := HoldTimer.Q;

(* Stop has priority over every other transition. *)
IF stop THEN
    ActiveStep := 0;
ELSE
    CASE ActiveStep OF
        0:
            IF start AND (r <> REGION_HIGH) THEN
                ActiveStep := 1;
            END_IF;
        1:
            IF settled OR (r = REGION_HIGH) THEN
                ActiveStep := 0;
            END_IF;
    ELSE
        ActiveStep := 0;
    END_CASE;
END_IF;

x0 := (ActiveStep = 0);
x1 := (ActiveStep = 1);

fill_valve := x1;
discharge_valve := x1;

FillValve := 0;
DischargeValve := 0;

IF x1 THEN
    (* PID demand is expressed in percent opening.
       Kp therefore has units of percent per level unit;
       Ti, Td and CycleSeconds are expressed in seconds. *)
    ProportionalTerm := Kp * LevelError;

    DerivativeTerm := 0.0;
    IF DerivativeReady AND (CycleSeconds > 0.0) AND (Td > 0.0) THEN
        DerivativeTerm :=
            Kp * Td * (LevelError - PreviousError) / CycleSeconds;
    END_IF;

    UnboundedDemand :=
        ProportionalTerm + IntegralTerm + DerivativeTerm;

    (* Freeze integration whenever the existing PID demand is clamped.
       Also reject an integral increment that would cause clamping. *)
    IntegrationEnabled :=
        (UnboundedDemand >= 0.0)
        AND (UnboundedDemand <= 100.0)
        AND (Ti > 0.0)
        AND (CycleSeconds > 0.0);

    IF IntegrationEnabled THEN
        IntegralCandidate :=
            IntegralTerm + Kp * LevelError * CycleSeconds / Ti;
        CandidateDemand :=
            ProportionalTerm + IntegralCandidate + DerivativeTerm;

        IF (CandidateDemand >= 0.0) AND (CandidateDemand <= 100.0) THEN
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

    FillValve :=
        REAL_TO_INT(BoundedDemand * INT_TO_REAL(FULL_SCALE) / 100.0);
    DischargeValve := REAL_TO_INT(0.4 * INT_TO_REAL(FULL_SCALE));

    PreviousError := LevelError;
    DerivativeReady := TRUE;
ELSE
    (* Retain the integral between runs; prime the derivative on restart. *)
    DerivativeReady := FALSE;
    IntegrationEnabled := FALSE;
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
    Controller : TankLevelController;
    Kp : REAL := 10.0;
    Ti : REAL := 10.0;
    Td : REAL := 0.0;
    h_span : REAL := 10.0;
    t_h : TIME := T#10s;
    (* Configure the OpenPLC task period to match this value. *)
    CycleSeconds : REAL := 0.02;
    fill_valve : BOOL;
    discharge_valve : BOOL;
END_VAR

Controller(
    StartCommand := StartCommand,
    StopCommand := StopCommand,
    LevelMeter := LevelMeter,
    Kp := Kp,
    Ti := Ti,
    Td := Td,
    CycleSeconds := CycleSeconds,
    h_span := h_span,
    t_h := t_h
);

FillValve := Controller.FillValve;
DischargeValve := Controller.DischargeValve;
fill_valve := Controller.fill_valve;
discharge_valve := Controller.discharge_valve;

END_PROGRAM
