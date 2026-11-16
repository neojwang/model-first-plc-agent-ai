FUNCTION_BLOCK FB_LevelControl
VAR_INPUT
    StartCommand : BOOL;
    StopCommand : BOOL;
    LevelMeter : INT;
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
    FillValve : INT;
    DischargeValve : INT;
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
    StateNumber : INT := 0;
    x0 : BOOL := TRUE;
    x1 : BOOL := FALSE;
    h : REAL;
    e : REAL;
    ErrorPercent : REAL;
    PreviousError : REAL := 0.0;
    IntegralTerm : REAL := 0.0;
    IntegralCandidate : REAL;
    ProportionalTerm : REAL;
    DerivativeTerm : REAL;
    UnboundedDemand : REAL;
    BoundedDemand : REAL;
    FirstPidScan : BOOL := TRUE;
END_VAR
VAR CONSTANT
    REGION_LOW : INT := 0;
    REGION_MIDDLE : INT := 1;
    REGION_HIGH : INT := 2;
END_VAR

StartEdge(CLK := StartCommand);
start := StartEdge.Q;
stop := StopCommand;

IF ScaleValue > 0 THEN
    h := INT_TO_REAL(LevelMeter) * h_span / INT_TO_REAL(ScaleValue);
ELSE
    h := 0.0;
END_IF;

e := h_sp - h;

IF h < h_target THEN
    r := REGION_LOW;
ELSIF h < h_max THEN
    r := REGION_MIDDLE;
ELSE
    r := REGION_HIGH;
END_IF;

(* Only uninterrupted time in tolerance during regulation qualifies. *)
HoldTimer(
    IN := (StateNumber = 1) AND NOT stop AND (ABS(e) <= eps),
    PT := t_h
);
settled := HoldTimer.Q;

IF stop THEN
    StateNumber := 0;
ELSE
    CASE StateNumber OF
        0:
            IF start THEN
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

(* Prevent even a single output scan when starting above the limit. *)
IF (StateNumber = 1) AND (r = REGION_HIGH) THEN
    StateNumber := 0;
END_IF;

x0 := StateNumber = 0;
x1 := StateNumber = 1;

fill_valve := x1;
discharge_valve := x1;

FillValve := 0;
DischargeValve := 0;

IF x1 THEN
    IF h_span > 0.0 THEN
        ErrorPercent := 100.0 * e / h_span;
    ELSE
        ErrorPercent := 0.0;
    END_IF;

    IF FirstPidScan THEN
        PreviousError := ErrorPercent;
        FirstPidScan := FALSE;
    END_IF;

    ProportionalTerm := Kp * ErrorPercent;

    DerivativeTerm := 0.0;
    IF (Td > 0.0) AND (CycleSeconds > 0.0) THEN
        DerivativeTerm :=
            Kp * Td * (ErrorPercent - PreviousError) / CycleSeconds;
    END_IF;

    (* Parallel PID with integral time Ti and derivative time Td.
       Demand and integral contribution are in percent opening. *)
    UnboundedDemand := ProportionalTerm + IntegralTerm + DerivativeTerm;

    (* Freeze integration whenever the current demand is saturated.
       Reject an integral update that would itself cause saturation. *)
    IF (UnboundedDemand >= 0.0) AND
       (UnboundedDemand <= 100.0) AND
       (Ti > 0.0) AND (CycleSeconds > 0.0) THEN
        IntegralCandidate :=
            IntegralTerm + Kp * ErrorPercent * CycleSeconds / Ti;

        UnboundedDemand :=
            ProportionalTerm + IntegralCandidate + DerivativeTerm;

        IF (UnboundedDemand >= 0.0) AND
           (UnboundedDemand <= 100.0) THEN
            IntegralTerm := IntegralCandidate;
        END_IF;
    END_IF;

    UnboundedDemand := ProportionalTerm + IntegralTerm + DerivativeTerm;

    IF UnboundedDemand > 100.0 THEN
        BoundedDemand := 100.0;
    ELSIF UnboundedDemand < 0.0 THEN
        BoundedDemand := 0.0;
    ELSE
        BoundedDemand := UnboundedDemand;
    END_IF;

    PreviousError := ErrorPercent;

    IF ScaleValue > 0 THEN
        FillValve :=
            REAL_TO_INT(BoundedDemand * INT_TO_REAL(ScaleValue) / 100.0);
        DischargeValve := REAL_TO_INT(0.4 * INT_TO_REAL(ScaleValue));
    END_IF;
ELSE
    IntegralTerm := 0.0;
    PreviousError := 0.0;
    FirstPidScan := TRUE;
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
    LevelController : FB_LevelControl;
    fill_valve : BOOL;
    discharge_valve : BOOL;

    h_span : REAL := 10.0;
    h_sp : REAL;
    h_target : REAL;
    h_max : REAL;
    eps : REAL;
    t_h : TIME := T#10s;

    (* Initial tuning values; adjust for the simulated plant. *)
    Kp : REAL := 1.0;
    Ti : REAL := 5.0;
    Td : REAL := 0.0;
END_VAR
VAR CONSTANT
    FULL_SCALE : INT := 1000;
    CONTROL_PERIOD_SECONDS : REAL := 0.02;
END_VAR

h_sp := 0.8 * h_span;
h_target := h_sp;
h_max := 0.9 * h_span;
eps := 0.02 * h_span;

LevelController(
    StartCommand := StartCommand,
    StopCommand := StopCommand,
    LevelMeter := LevelMeter,
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
    CycleSeconds := CONTROL_PERIOD_SECONDS,
    FillValve => FillValve,
    DischargeValve => DischargeValve,
    fill_valve => fill_valve,
    discharge_valve => discharge_valve
);

END_PROGRAM


CONFIGURATION Config0
RESOURCE Res0 ON PLC
    TASK ControlTask(INTERVAL := T#20ms, PRIORITY := 0);
    PROGRAM MainInstance WITH ControlTask : Main;
END_RESOURCE
END_CONFIGURATION
