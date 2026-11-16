FUNCTION_BLOCK FB_LevelControl
VAR_INPUT
    StartCommand : BOOL;
    StopCommand : BOOL;
    LevelMeter : INT;
    h_span : REAL;
    h_sp : REAL;
    h_target : REAL;
    h_max : REAL;
    eps : REAL;
    t_h : TIME;
    Kp : REAL;
    Ti : REAL;
    Td : REAL;
    CycleTime : TIME;
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
    x0 : BOOL := TRUE;
    x1 : BOOL := FALSE;
    WasRegulating : BOOL := FALSE;
    h : REAL;
    e : REAL;
    PreviousError : REAL := 0.0;
    SampleSeconds : REAL;
    ProportionalTerm : REAL;
    IntegralTerm : REAL := 0.0;
    IntegralCandidate : REAL;
    DerivativeTerm : REAL;
    UnboundedDemand : REAL;
    CandidateDemand : REAL;
    BoundedDemand : REAL;
END_VAR

StartEdge(CLK := StartCommand);
start := StartEdge.Q;
stop := StopCommand;

h := INT_TO_REAL(LevelMeter) * h_span / INT_TO_REAL(FULL_SCALE);
e := h_sp - h;

IF h < h_target THEN
    r := REGION_LOW;
ELSIF h < h_max THEN
    r := REGION_MIDDLE;
ELSE
    r := REGION_HIGH;
END_IF;

SampleSeconds := TIME_TO_REAL(CycleTime) / 1000.0;
IF SampleSeconds <= 0.0 THEN
    SampleSeconds := 0.02;
END_IF;

(* The hold interval is continuous and belongs only to regulation. *)
HoldTimer(
    IN := (StateNumber = 1) AND NOT stop AND (ABS(e) <= eps),
    PT := t_h
);
settled := HoldTimer.Q;

(* Stop overrides every normal transition. *)
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

(* Stabilize an immediately enabled overfill termination without
   issuing a one-scan valve command. *)
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
    IF NOT WasRegulating THEN
        IntegralTerm := 0.0;
        PreviousError := e;
    END_IF;

    (* Parallel PID:
       demand = Kp * (e + integral(e)/Ti + Td * derivative(e)).
       Demand is expressed in percent of valve opening.
       Kp therefore has units of percent per level unit.
       Nonpositive Ti disables integration. *)
    ProportionalTerm := Kp * e;
    DerivativeTerm := Kp * Td * (e - PreviousError) / SampleSeconds;

    IF Ti <= 0.0 THEN
        IntegralTerm := 0.0;
    END_IF;

    UnboundedDemand := ProportionalTerm + IntegralTerm + DerivativeTerm;
    IntegralCandidate := IntegralTerm;

    (* Freeze integration whenever the current output is clamped.
       Also reject an integration increment that would cross a limit. *)
    IF (Ti > 0.0)
        AND (UnboundedDemand >= 0.0)
        AND (UnboundedDemand <= 100.0) THEN
        IntegralCandidate := IntegralTerm
            + Kp * e * SampleSeconds / Ti;
        CandidateDemand := ProportionalTerm
            + IntegralCandidate + DerivativeTerm;

        IF (CandidateDemand >= 0.0) AND (CandidateDemand <= 100.0) THEN
            IntegralTerm := IntegralCandidate;
        END_IF;
    END_IF;

    UnboundedDemand := ProportionalTerm + IntegralTerm + DerivativeTerm;

    IF UnboundedDemand < 0.0 THEN
        BoundedDemand := 0.0;
    ELSIF UnboundedDemand > 100.0 THEN
        BoundedDemand := 100.0;
    ELSE
        BoundedDemand := UnboundedDemand;
    END_IF;

    FillValve := REAL_TO_INT(
        BoundedDemand * INT_TO_REAL(FULL_SCALE) / 100.0
    );
    DischargeValve := REAL_TO_INT(0.4 * INT_TO_REAL(FULL_SCALE));

    PreviousError := e;
ELSE
    IntegralTerm := 0.0;
    PreviousError := e;
    BoundedDemand := 0.0;
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
VAR
    Controller : FB_LevelControl;
    h_span : REAL := 10.0;
    h_sp : REAL := 8.0;
    h_target : REAL := 8.0;
    h_max : REAL := 9.0;
    eps : REAL := 0.2;
    t_h : TIME := T#10s;

    (* Initial tuning values; commission against the actual plant. *)
    Kp : REAL := 10.0;
    Ti : REAL := 10.0;
    Td : REAL := 0.0;

    (* Must match the configured cyclic task interval. *)
    CycleTime : TIME := T#20ms;
    fill_valve : BOOL;
    discharge_valve : BOOL;
END_VAR

Controller(
    StartCommand := StartCommand,
    StopCommand := StopCommand,
    LevelMeter := LevelMeter,
    h_span := h_span,
    h_sp := h_sp,
    h_target := h_target,
    h_max := h_max,
    eps := eps,
    t_h := t_h,
    Kp := Kp,
    Ti := Ti,
    Td := Td,
    CycleTime := CycleTime
);

FillValve := Controller.FillValve;
DischargeValve := Controller.DischargeValve;
fill_valve := Controller.fill_valve;
discharge_valve := Controller.discharge_valve;

END_PROGRAM
