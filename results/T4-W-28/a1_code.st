FUNCTION_BLOCK LevelControlRuntime
VAR_INPUT
    StartInput : BOOL;
    StopInput : BOOL;
    LevelInput : INT;
    ScaleValue : INT;
    h_span : REAL;
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
VAR CONSTANT
    REGION_LOW : INT := 0;
    REGION_MID : INT := 1;
    REGION_HIGH : INT := 2;
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
    t1 : BOOL;
    t2 : BOOL;

    h : REAL;
    e : REAL;
    PreviousError : REAL := 0.0;
    IntegralTerm : REAL := 0.0;
    IntegralCandidate : REAL;
    ProportionalTerm : REAL;
    DerivativeTerm : REAL;
    RawDemand : REAL;
    CandidateDemand : REAL;
    LimitedDemand : REAL;
END_VAR

StartEdge(CLK := StartInput);
start := StartEdge.Q;
stop := StopInput;

h := INT_TO_REAL(LevelInput) * h_span / INT_TO_REAL(ScaleValue);
e := h_target - h;

IF h < h_target THEN
    r := REGION_LOW;
ELSIF h < h_max THEN
    r := REGION_MID;
ELSE
    r := REGION_HIGH;
END_IF;

(* The nonretentive timer measures uninterrupted tolerance residence
   only while x1 is active. Its initial value on entry is FALSE. *)
HoldTimer(
    IN := x1 AND (ABS(e) <= eps) AND NOT stop,
    PT := t_h
);
settled := HoldTimer.Q;

(* Evaluate both transitions against the same preceding situation. *)
t1 := x0 AND start AND NOT stop AND NOT (r = REGION_HIGH);
t2 := x1 AND (stop OR settled OR (r = REGION_HIGH));

IF t1 THEN
    x0 := FALSE;
    x1 := TRUE;

    (* Initialize the controller for a new regulation cycle. *)
    IntegralTerm := 0.0;
    PreviousError := e;
ELSIF t2 THEN
    x0 := TRUE;
    x1 := FALSE;
END_IF;

fill_valve := x1;
discharge_valve := x1;

FillCommand := 0;
DischargeCommand := 0;

IF fill_valve THEN
    ProportionalTerm := Kp * e;
    DerivativeTerm := 0.0;

    IF (CycleSeconds > 0.0) AND (Td > 0.0) THEN
        DerivativeTerm :=
            Kp * Td * (e - PreviousError) / CycleSeconds;
    END_IF;

    IF Ti <= 0.0 THEN
        (* Nonpositive Ti disables integral action. *)
        IntegralTerm := 0.0;
    END_IF;

    RawDemand := ProportionalTerm + IntegralTerm + DerivativeTerm;

    (* Suspend integration whenever the demand is clamped.
       Reject an integral update that would itself cause clamping. *)
    IF (RawDemand >= 0.0) AND (RawDemand <= 100.0) THEN
        IF (Ti > 0.0) AND (CycleSeconds > 0.0) THEN
            IntegralCandidate :=
                IntegralTerm + Kp * e * CycleSeconds / Ti;
            CandidateDemand :=
                ProportionalTerm + IntegralCandidate + DerivativeTerm;

            IF (CandidateDemand >= 0.0) AND
               (CandidateDemand <= 100.0) THEN
                IntegralTerm := IntegralCandidate;
                RawDemand := CandidateDemand;
            END_IF;
        END_IF;
    END_IF;

    IF RawDemand > 100.0 THEN
        LimitedDemand := 100.0;
    ELSIF RawDemand < 0.0 THEN
        LimitedDemand := 0.0;
    ELSE
        LimitedDemand := RawDemand;
    END_IF;

    FillCommand :=
        REAL_TO_INT(LimitedDemand * INT_TO_REAL(ScaleValue) / 100.0);
    PreviousError := e;
ELSE
    IntegralTerm := 0.0;
    PreviousError := e;
    LimitedDemand := 0.0;
END_IF;

IF discharge_valve THEN
    DischargeCommand := REAL_TO_INT(0.4 * INT_TO_REAL(ScaleValue));
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
    CycleSeconds : REAL := 0.02;
END_VAR
VAR
    Controller : LevelControlRuntime;

    h_span : REAL := 10.0;
    h_sp : REAL;
    h_target : REAL;
    h_max : REAL;
    eps : REAL;
    t_h : TIME := T#10s;

    (* Commissioning parameters: Kp is percent opening per volt;
       Ti and Td are expressed in seconds. *)
    Kp : REAL := 10.0;
    Ti : REAL := 10.0;
    Td : REAL := 0.0;
END_VAR

h_sp := 0.8 * h_span;
h_target := h_sp;
h_max := 0.9 * h_span;
eps := 0.02 * h_span;

Controller(
    StartInput := StartCommand,
    StopInput := StopCommand,
    LevelInput := LevelMeter,
    ScaleValue := FULL_SCALE,
    h_span := h_span,
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


CONFIGURATION Config0
    RESOURCE Res0 ON PLC
        TASK MainTask(INTERVAL := T#20ms, PRIORITY := 0);
        PROGRAM MainInstance WITH MainTask : Main;
    END_RESOURCE
END_CONFIGURATION
