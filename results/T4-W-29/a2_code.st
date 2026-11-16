FUNCTION_BLOCK FB_LevelControl
VAR_INPUT
    StartCommand : BOOL;
    StopCommand : BOOL;
    LevelMeter : INT;
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
    (* Region encoding: 0 = LOW, 1 = MID, 2 = HIGH. *)
    r : INT;
    StateNumber : INT := 0;
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
    RawDemand : REAL;
    LimitedDemand : REAL;
END_VAR

StartEdge(CLK := StartCommand);
start := StartEdge.Q;
stop := StopCommand;

h := INT_TO_REAL(LevelMeter) * h_span / INT_TO_REAL(FullScaleValue);
e := h_sp - h;

IF h < h_target THEN
    r := 0;
ELSIF h < h_max THEN
    r := 1;
ELSE
    r := 2;
END_IF;

(* The hold interval qualifies only while regulation is active
   and the error remains continuously inside the tolerance band. *)
HoldTimer(
    IN := (StateNumber = 1) AND NOT stop
          AND (ABS(e) <= eps) AND (r <> 2),
    PT := t_h
);
settled := HoldTimer.Q;

(* Stop has priority over every normal transition. *)
IF stop THEN
    StateNumber := 0;
ELSE
    CASE StateNumber OF
        0:
            IF start AND (r <> 2) THEN
                StateNumber := 1;
            END_IF;
        1:
            IF settled OR (r = 2) THEN
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

(* Default commands also enforce zero outputs in the initial step. *)
FillValve := 0;
DischargeValve := 0;

IF x1 THEN
    IF NOT WasRegulating THEN
        IntegralTerm := 0.0;
        PreviousError := e;
    END_IF;

    (* PID demand is expressed as a fraction of full valve opening.
       Ti and Td are expressed in seconds; Ti <= 0 disables integration. *)
    ProportionalTerm := Kp * e;
    DerivativeTerm := 0.0;

    IF (Td > 0.0) AND (CycleSeconds > 0.0) THEN
        DerivativeTerm :=
            Kp * Td * (e - PreviousError) / CycleSeconds;
    END_IF;

    RawDemand := ProportionalTerm + IntegralTerm + DerivativeTerm;
    CandidateIntegral := IntegralTerm;

    (* Freeze integration whenever the current output is saturated.
       Also reject an integration increment that would cause saturation. *)
    IF (RawDemand >= 0.0) AND (RawDemand <= 1.0)
       AND (Ti > 0.0) AND (CycleSeconds > 0.0) THEN
        CandidateIntegral :=
            IntegralTerm + Kp * e * CycleSeconds / Ti;
        CandidateDemand :=
            ProportionalTerm + CandidateIntegral + DerivativeTerm;

        IF (CandidateDemand >= 0.0) AND (CandidateDemand <= 1.0) THEN
            IntegralTerm := CandidateIntegral;
        END_IF;
    END_IF;

    RawDemand := ProportionalTerm + IntegralTerm + DerivativeTerm;

    IF RawDemand < 0.0 THEN
        LimitedDemand := 0.0;
    ELSIF RawDemand > 1.0 THEN
        LimitedDemand := 1.0;
    ELSE
        LimitedDemand := RawDemand;
    END_IF;

    FillValve := REAL_TO_INT(
        LimitedDemand * INT_TO_REAL(FullScaleValue)
    );
    DischargeValve := REAL_TO_INT(
        0.4 * INT_TO_REAL(FullScaleValue)
    );

    PreviousError := e;
ELSE
    IntegralTerm := 0.0;
    PreviousError := e;
    LimitedDemand := 0.0;
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
END_VAR
VAR
    Controller : FB_LevelControl;
    h_span : REAL := 10.0;
    h_sp : REAL;
    h_target : REAL;
    h_max : REAL;
    eps : REAL;
    t_h : TIME := T#10s;
    (* Commissioning defaults; tune these gains for the plant.
       Kp is valve-opening fraction per level unit (here, volts). *)
    Kp : REAL := 0.5;
    Ti : REAL := 5.0;
    Td : REAL := 0.0;
    CycleSeconds : REAL := 0.02;
    fill_valve : BOOL;
    discharge_valve : BOOL;
END_VAR

h_sp := 0.8 * h_span;
h_target := h_sp;
h_max := 0.9 * h_span;
eps := 0.02 * h_span;

Controller(
    StartCommand := StartCommand,
    StopCommand := StopCommand,
    LevelMeter := LevelMeter,
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

FillValve := Controller.FillValve;
DischargeValve := Controller.DischargeValve;
fill_valve := Controller.fill_valve;
discharge_valve := Controller.discharge_valve;

END_PROGRAM


CONFIGURATION Config0
    RESOURCE Res0 ON PLC
        TASK MainTask(INTERVAL := T#20ms, PRIORITY := 0);
        PROGRAM MainInstance WITH MainTask : Main;
    END_RESOURCE
END_CONFIGURATION
