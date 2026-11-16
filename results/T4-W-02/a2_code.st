FUNCTION_BLOCK FB_LevelControl
VAR_INPUT
    StartCommand : BOOL;
    StopCommand : BOOL;
    LevelMeter : INT;
    FULL_SCALE : INT;
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
    h : REAL;
    ErrorValue : REAL;
    PreviousError : REAL := 0.0;
    IntegralTerm : REAL := 0.0;
    ProportionalTerm : REAL;
    DerivativeTerm : REAL;
    CandidateIntegral : REAL;
    CandidateDemand : REAL;
    RawDemand : REAL;
    BoundedDemand : REAL;
    DerivativeReady : BOOL := FALSE;
END_VAR

(* Region encoding: 0 = LOW, 1 = middle region, 2 = HIGH. *)
StartEdge(CLK := StartCommand);
start := StartEdge.Q;
stop := StopCommand;

IF FULL_SCALE > 0 THEN
    h := INT_TO_REAL(LevelMeter) * h_span / INT_TO_REAL(FULL_SCALE);
ELSE
    h := 0.0;
END_IF;

ErrorValue := h_sp - h;

IF h < h_target THEN
    r := 0;
ELSIF h < h_max THEN
    r := 1;
ELSE
    r := 2;
END_IF;

HoldTimer(
    IN := (StateNumber = 1) AND NOT stop
          AND (ABS(ErrorValue) <= eps),
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
            IF settled OR (r = 2) THEN
                StateNumber := 0;
            END_IF;
    ELSE
        StateNumber := 0;
    END_CASE;
END_IF;

(* Prevent an output pulse when starting at the overfill limit. *)
IF (StateNumber = 1) AND (r = 2) THEN
    StateNumber := 0;
END_IF;

fill_valve := (StateNumber = 1);
discharge_valve := (StateNumber = 1);

FillValve := 0;
DischargeValve := 0;

IF fill_valve THEN
    (* PID demand is expressed as a fraction of full valve opening. *)
    IF h_span > 0.0 THEN
        ProportionalTerm := Kp * ErrorValue / h_span;
    ELSE
        ProportionalTerm := 0.0;
    END_IF;

    DerivativeTerm := 0.0;
    IF DerivativeReady AND (CycleSeconds > 0.0)
       AND (h_span > 0.0) THEN
        DerivativeTerm := Kp * Td
                          * (ErrorValue - PreviousError)
                          / (h_span * CycleSeconds);
    END_IF;

    RawDemand := ProportionalTerm + IntegralTerm + DerivativeTerm;

    (* Suspend integration whenever the demand is clamped.
       Reject an integration increment that would cause saturation. *)
    IF (RawDemand >= 0.0) AND (RawDemand <= 1.0)
       AND (Ti > 0.0) AND (CycleSeconds > 0.0)
       AND (h_span > 0.0) THEN
        CandidateIntegral := IntegralTerm
                             + Kp * ErrorValue * CycleSeconds
                               / (h_span * Ti);
        CandidateDemand := ProportionalTerm
                           + CandidateIntegral + DerivativeTerm;

        IF (CandidateDemand >= 0.0) AND (CandidateDemand <= 1.0) THEN
            IntegralTerm := CandidateIntegral;
            RawDemand := CandidateDemand;
        END_IF;
    END_IF;

    IF RawDemand < 0.0 THEN
        BoundedDemand := 0.0;
    ELSIF RawDemand > 1.0 THEN
        BoundedDemand := 1.0;
    ELSE
        BoundedDemand := RawDemand;
    END_IF;

    IF FULL_SCALE > 0 THEN
        FillValve := REAL_TO_INT(BoundedDemand * INT_TO_REAL(FULL_SCALE));
    END_IF;

    PreviousError := ErrorValue;
    DerivativeReady := TRUE;
ELSE
    IntegralTerm := 0.0;
    PreviousError := ErrorValue;
    DerivativeReady := FALSE;
END_IF;

IF discharge_valve AND (FULL_SCALE > 0) THEN
    DischargeValve := REAL_TO_INT(0.4 * INT_TO_REAL(FULL_SCALE));
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
    LevelController : FB_LevelControl;
    h_span : REAL := 10.0;
    h_sp : REAL;
    h_target : REAL;
    h_max : REAL;
    eps : REAL;
    t_h : TIME := T#10s;
    (* Initial tuning values; adjust for the simulated plant. *)
    Kp : REAL := 2.0;
    Ti : REAL := 5.0;
    Td : REAL := 0.0;
    CycleSeconds : REAL := 0.02;
END_VAR

h_sp := 0.8 * h_span;
h_target := h_sp;
h_max := 0.9 * h_span;
eps := 0.02 * h_span;

LevelController(
    StartCommand := StartCommand,
    StopCommand := StopCommand,
    LevelMeter := LevelMeter,
    FULL_SCALE := FULL_SCALE,
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

FillValve := LevelController.FillValve;
DischargeValve := LevelController.DischargeValve;

END_PROGRAM


CONFIGURATION Config0
    RESOURCE Res0 ON PLC
        TASK MainTask(INTERVAL := T#20ms, PRIORITY := 0);
        PROGRAM MainInstance WITH MainTask : Main;
    END_RESOURCE
END_CONFIGURATION
