FUNCTION_BLOCK FB_LevelControl
VAR_INPUT
    StartCommand : BOOL;
    StopCommand : BOOL;
    LevelMeter : INT;
    Kp : REAL := 100.0;
    Ti : REAL := 10.0;
    Td : REAL := 0.0;
    CycleSeconds : REAL := 0.02;
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
    t_h : TIME := T#10s;
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
    StateCode : INT := 0;
    x0 : BOOL := TRUE;
    x1 : BOOL := FALSE;
    h : REAL;
    h_sp : REAL;
    h_target : REAL;
    h_max : REAL;
    eps : REAL;
    ErrorValue : REAL;
    PreviousError : REAL := 0.0;
    IntegralTerm : REAL := 0.0;
    CandidateIntegral : REAL;
    ProportionalTerm : REAL;
    DerivativeTerm : REAL;
    RawDemand : REAL;
    BoundedDemand : REAL;
    PidActive : BOOL := FALSE;
END_VAR

(* Level values are expressed in volts; PID demand is in percent. *)
h := INT_TO_REAL(LevelMeter) * h_span / INT_TO_REAL(FULL_SCALE);
h_sp := 0.8 * h_span;
h_target := h_sp;
h_max := 0.9 * h_span;
eps := 0.02 * h_span;
ErrorValue := h_sp - h;

StartEdge(CLK := StartCommand);
start := StartEdge.Q;
stop := StopCommand;

IF h < h_target THEN
    r := REGION_LOW;
ELSIF h < h_max THEN
    r := REGION_MIDDLE;
ELSE
    r := REGION_HIGH;
END_IF;

(* Only consecutive in-band time during regulation is accumulated. *)
HoldTimer(
    IN := (StateCode = 1) AND NOT stop
          AND (ABS(ErrorValue) <= eps),
    PT := t_h
);
settled := HoldTimer.Q;

IF stop THEN
    StateCode := 0;
ELSE
    CASE StateCode OF
        0:
            IF start AND (r <> REGION_HIGH) THEN
                StateCode := 1;
            END_IF;
        1:
            IF settled OR (r = REGION_HIGH) THEN
                StateCode := 0;
            END_IF;
    ELSE
        StateCode := 0;
    END_CASE;
END_IF;

x0 := StateCode = 0;
x1 := StateCode = 1;

fill_valve := x1;
discharge_valve := x1;

IF x0 THEN
    HoldTimer(IN := FALSE, PT := t_h);
    settled := FALSE;
END_IF;

FillValve := 0;
DischargeValve := 0;

IF fill_valve THEN
    IF NOT PidActive THEN
        IntegralTerm := 0.0;
        PreviousError := ErrorValue;
    END_IF;

    ProportionalTerm := Kp * ErrorValue;
    DerivativeTerm := 0.0;

    IF CycleSeconds > 0.0 THEN
        DerivativeTerm :=
            Kp * Td * (ErrorValue - PreviousError) / CycleSeconds;
    END_IF;

    (* Test the current output before permitting integration. *)
    RawDemand := ProportionalTerm + IntegralTerm + DerivativeTerm;
    CandidateIntegral := IntegralTerm;

    IF (RawDemand >= 0.0) AND (RawDemand <= 100.0)
       AND (Ti > 0.0) AND (CycleSeconds > 0.0) THEN
        CandidateIntegral :=
            IntegralTerm + Kp * ErrorValue * CycleSeconds / Ti;

        RawDemand :=
            ProportionalTerm + CandidateIntegral + DerivativeTerm;

        (* Suspend integration if the candidate output is clamped. *)
        IF (RawDemand >= 0.0) AND (RawDemand <= 100.0) THEN
            IntegralTerm := CandidateIntegral;
        END_IF;
    END_IF;

    IF RawDemand > 100.0 THEN
        BoundedDemand := 100.0;
    ELSIF RawDemand < 0.0 THEN
        BoundedDemand := 0.0;
    ELSE
        BoundedDemand := RawDemand;
    END_IF;

    FillValve := REAL_TO_INT(
        BoundedDemand * INT_TO_REAL(FULL_SCALE) / 100.0
    );

    PreviousError := ErrorValue;
    PidActive := TRUE;
ELSE
    IntegralTerm := 0.0;
    PreviousError := ErrorValue;
    PidActive := FALSE;
END_IF;

IF discharge_valve THEN
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
VAR
    LevelController : FB_LevelControl;
    (* Initial tuning values; adjust to suit the simulated plant. *)
    Kp : REAL := 100.0;
    Ti : REAL := 10.0;
    Td : REAL := 0.0;
END_VAR

LevelController(
    StartCommand := StartCommand,
    StopCommand := StopCommand,
    LevelMeter := LevelMeter,
    Kp := Kp,
    Ti := Ti,
    Td := Td,
    CycleSeconds := 0.02
);

FillValve := LevelController.FillValve;
DischargeValve := LevelController.DischargeValve;

END_PROGRAM


CONFIGURATION Config0
    RESOURCE Res0 ON PLC
        TASK ControlTask(INTERVAL := T#20ms, PRIORITY := 0);
        PROGRAM MainInstance WITH ControlTask : Main;
    END_RESOURCE
END_CONFIGURATION
