FUNCTION_BLOCK FB_LevelControl
VAR_INPUT
    StartCommand : BOOL;
    StopCommand : BOOL;
    LevelMeter : INT;
    Kp : REAL := 1.0;
    Ti : REAL := 10.0;
    Td : REAL := 0.0;
END_VAR
VAR_OUTPUT
    FillValve : INT;
    DischargeValve : INT;
    fill_valve : BOOL;
    discharge_valve : BOOL;
END_VAR
VAR CONSTANT
    FULL_SCALE : INT := 1000;
    h_span : REAL := 10.0;
    h_sp : REAL := 8.0;
    h_target : REAL := 8.0;
    h_max : REAL := 9.0;
    eps : REAL := 0.2;
    t_h : TIME := T#10s;
    ScanSeconds : REAL := 0.02;
    RegionLow : INT := 0;
    RegionMiddle : INT := 1;
    RegionHigh : INT := 2;
END_VAR
VAR
    StartEdge : R_TRIG;
    HoldTimer : TON;
    start : BOOL;
    stop : BOOL;
    settled : BOOL;
    r : INT;
    SequenceState : INT := 0;
    x0 : BOOL := TRUE;
    x1 : BOOL := FALSE;
    WasRegulating : BOOL := FALSE;
    h : REAL;
    e : REAL;
    PreviousError : REAL := 0.0;
    IntegralTerm : REAL := 0.0;
    CandidateIntegral : REAL;
    ProportionalTerm : REAL;
    DerivativeTerm : REAL;
    CandidateDemand : REAL;
    BoundedDemand : REAL;
END_VAR

(* Generate a one-scan start event, including while stopped. *)
StartEdge(CLK := StartCommand);
start := StartEdge.Q;
stop := StopCommand;

h := INT_TO_REAL(LevelMeter) * h_span / INT_TO_REAL(FULL_SCALE);
e := h_sp - h;

IF h < h_target THEN
    r := RegionLow;
ELSIF h < h_max THEN
    r := RegionMiddle;
ELSE
    r := RegionHigh;
END_IF;

(* The hold timer measures uninterrupted time in band during x1. *)
HoldTimer(
    IN := (SequenceState = 1) AND NOT stop AND (ABS(e) <= eps),
    PT := t_h
);
settled := HoldTimer.Q;

(* Stop has unconditional priority over every sequence transition. *)
IF stop THEN
    SequenceState := 0;
ELSE
    CASE SequenceState OF
        0:
            IF start THEN
                SequenceState := 1;
            END_IF;
        1:
            IF settled OR (r = RegionHigh) THEN
                SequenceState := 0;
            END_IF;
    ELSE
        SequenceState := 0;
    END_CASE;
END_IF;

(* Resolve an immediately satisfied overfill termination on entry. *)
IF (SequenceState = 1) AND (r = RegionHigh) THEN
    SequenceState := 0;
END_IF;

x0 := SequenceState = 0;
x1 := SequenceState = 1;
fill_valve := x1;
discharge_valve := x1;

(* Outputs are explicitly zero whenever regulation is inactive. *)
FillValve := 0;
DischargeValve := 0;

IF fill_valve THEN
    IF NOT WasRegulating THEN
        IntegralTerm := 0.0;
        PreviousError := e;
    END_IF;

    (* Parallel PID; demand is a fraction of full valve opening.
       Ti and Td are in seconds; Ti <= 0 disables integration. *)
    ProportionalTerm := Kp * e;

    IF Td > 0.0 THEN
        DerivativeTerm :=
            Kp * Td * (e - PreviousError) / ScanSeconds;
    ELSE
        DerivativeTerm := 0.0;
    END_IF;

    CandidateIntegral := IntegralTerm;
    IF Ti > 0.0 THEN
        CandidateIntegral :=
            IntegralTerm + Kp * e * ScanSeconds / Ti;
    ELSE
        CandidateIntegral := 0.0;
        IntegralTerm := 0.0;
    END_IF;

    CandidateDemand :=
        ProportionalTerm + CandidateIntegral + DerivativeTerm;

    (* Clamp the demand and reject the integral update whenever
       the calculated output is clamped. *)
    IF CandidateDemand > 1.0 THEN
        BoundedDemand := 1.0;
    ELSIF CandidateDemand < 0.0 THEN
        BoundedDemand := 0.0;
    ELSE
        BoundedDemand := CandidateDemand;
        IntegralTerm := CandidateIntegral;
    END_IF;

    FillValve :=
        REAL_TO_INT(BoundedDemand * INT_TO_REAL(FULL_SCALE));

    IF discharge_valve THEN
        DischargeValve :=
            REAL_TO_INT(0.4 * INT_TO_REAL(FULL_SCALE));
    END_IF;

    PreviousError := e;
ELSE
    IntegralTerm := 0.0;
    PreviousError := e;
    BoundedDemand := 0.0;
END_IF;

WasRegulating := fill_valve;

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
    Kp : REAL := 1.0;
    Ti : REAL := 10.0;
    Td : REAL := 0.0;
END_VAR

(* Initial gain values require tuning for the simulated plant. *)
LevelController(
    StartCommand := StartCommand,
    StopCommand := StopCommand,
    LevelMeter := LevelMeter,
    Kp := Kp,
    Ti := Ti,
    Td := Td
);

FillValve := LevelController.FillValve;
DischargeValve := LevelController.DischargeValve;

END_PROGRAM


CONFIGURATION Config0
RESOURCE Res0 ON PLC
    (* Must match ScanSeconds in FB_LevelControl. *)
    TASK ControlTask(INTERVAL := T#20ms, PRIORITY := 0);
    PROGRAM MainInstance WITH ControlTask : Main;
END_RESOURCE
END_CONFIGURATION
