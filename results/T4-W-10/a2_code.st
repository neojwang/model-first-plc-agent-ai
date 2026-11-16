FUNCTION_BLOCK FB_LevelControl
VAR_INPUT
    StartCommand : BOOL;
    StopCommand : BOOL;
    LevelMeter : INT;
    h_span : REAL := 10.0;
    Kp : REAL := 50.0;
    Ti : REAL := 5.0;
    Td : REAL := 0.0;
    t_h : TIME := T#10s;
    CycleSeconds : REAL := 0.1;
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

    StateNumber : INT := 0;
    WasRegulating : BOOL;
    x0 : BOOL := TRUE;
    x1 : BOOL := FALSE;

    h : REAL;
    h_sp : REAL;
    h_target : REAL;
    h_max : REAL;
    eps : REAL;
    ErrorValue : REAL;
    PreviousError : REAL := 0.0;

    ProportionalTerm : REAL;
    IntegralTerm : REAL := 0.0;
    DerivativeTerm : REAL;
    IntegralCandidate : REAL;
    CandidateDemand : REAL;
    RawDemand : REAL;
    BoundedDemand : REAL;
    EffectiveCycle : REAL;
END_VAR

StartEdge(CLK := StartCommand);
start := StartEdge.Q;
stop := StopCommand;

h := INT_TO_REAL(LevelMeter) * h_span / INT_TO_REAL(FULL_SCALE);
h_sp := 0.8 * h_span;
h_target := h_sp;
h_max := 0.9 * h_span;
eps := 0.02 * h_span;
ErrorValue := h_sp - h;

IF h < h_target THEN
    r := REGION_LOW;
ELSIF h < h_max THEN
    r := REGION_MIDDLE;
ELSE
    r := REGION_HIGH;
END_IF;

EffectiveCycle := CycleSeconds;
IF EffectiveCycle <= 0.0 THEN
    EffectiveCycle := 0.1;
END_IF;

WasRegulating := StateNumber = 1;

(* The hold condition measures uninterrupted time in tolerance
   during regulation, not merely the duration of step x1. *)
HoldTimer(
    IN := WasRegulating AND NOT stop
          AND (ABS(ErrorValue) <= eps),
    PT := t_h
);
settled := HoldTimer.Q;

(* Stop has unconditional priority over every sequence transition. *)
IF stop THEN
    StateNumber := 0;
ELSE
    CASE StateNumber OF
        0:
            IF start AND (r <> REGION_HIGH) THEN
                StateNumber := 1;
            END_IF;
        1:
            IF settled OR (r = REGION_HIGH) THEN
                StateNumber := 0;
            END_IF;
    ELSE
        StateNumber := 0;
    END_CASE;
END_IF;

x0 := StateNumber = 0;
x1 := StateNumber = 1;
fill_valve := x1;
discharge_valve := x1;

(* Safe defaults are assigned on every invocation. *)
FillValve := 0;
DischargeValve := 0;

IF x1 THEN
    IF NOT WasRegulating THEN
        IntegralTerm := 0.0;
        PreviousError := ErrorValue;
    END_IF;

    (* Parallel PID: output units are percent valve opening. *)
    ProportionalTerm := Kp * ErrorValue;
    DerivativeTerm :=
        Kp * Td * (ErrorValue - PreviousError) / EffectiveCycle;

    RawDemand := ProportionalTerm + IntegralTerm + DerivativeTerm;

    (* Suspend integration whenever the current output is clamped.
       Also reject an integral increment that would cause clamping. *)
    IF (RawDemand >= 0.0) AND (RawDemand <= 100.0)
       AND (Ti > 0.0) THEN
        IntegralCandidate :=
            IntegralTerm + Kp * ErrorValue * EffectiveCycle / Ti;
        CandidateDemand :=
            ProportionalTerm + IntegralCandidate + DerivativeTerm;

        IF (CandidateDemand >= 0.0)
           AND (CandidateDemand <= 100.0) THEN
            IntegralTerm := IntegralCandidate;
        END_IF;
    END_IF;

    RawDemand := ProportionalTerm + IntegralTerm + DerivativeTerm;

    IF RawDemand < 0.0 THEN
        BoundedDemand := 0.0;
    ELSIF RawDemand > 100.0 THEN
        BoundedDemand := 100.0;
    ELSE
        BoundedDemand := RawDemand;
    END_IF;

    FillValve := REAL_TO_INT(
        BoundedDemand * INT_TO_REAL(FULL_SCALE) / 100.0
    );
    DischargeValve := REAL_TO_INT(0.4 * INT_TO_REAL(FULL_SCALE));

    PreviousError := ErrorValue;
ELSE
    IntegralTerm := 0.0;
    PreviousError := ErrorValue;
    DerivativeTerm := 0.0;
    RawDemand := 0.0;
    BoundedDemand := 0.0;
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
    Controller : FB_LevelControl;
    h_span : REAL := 10.0;
    Kp : REAL := 50.0;
    Ti : REAL := 5.0;
    Td : REAL := 0.0;
    t_h : TIME := T#10s;
    CycleSeconds : REAL := 0.1;
    fill_valve : BOOL;
    discharge_valve : BOOL;
END_VAR

Controller(
    StartCommand := StartCommand,
    StopCommand := StopCommand,
    LevelMeter := LevelMeter,
    h_span := h_span,
    Kp := Kp,
    Ti := Ti,
    Td := Td,
    t_h := t_h,
    CycleSeconds := CycleSeconds
);

FillValve := Controller.FillValve;
DischargeValve := Controller.DischargeValve;
fill_valve := Controller.fill_valve;
discharge_valve := Controller.discharge_valve;

END_PROGRAM


CONFIGURATION Config0
    RESOURCE Res0 ON PLC
        TASK ControlTask(INTERVAL := T#100ms, PRIORITY := 0);
        PROGRAM MainInstance WITH ControlTask : Main;
    END_RESOURCE
END_CONFIGURATION
