FUNCTION_BLOCK LevelControlRuntime
VAR_INPUT
    StartCommand : BOOL;
    StopCommand : BOOL;
    LevelMeter : INT;
    FullScaleValue : INT;
    h_span : REAL;
    h_target : REAL;
    h_sp : REAL;
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

    x0 : BOOL := TRUE;
    x1 : BOOL := FALSE;
    WasRegulating : BOOL;
    EnteredRegulation : BOOL;

    h : REAL;
    e : REAL;
    PreviousError : REAL := 0.0;
    IntegralTerm : REAL := 0.0;
    TrialIntegral : REAL;
    ProportionalTerm : REAL;
    DerivativeTerm : REAL;
    TrialDemand : REAL;
    Demand : REAL;
    LimitedDemand : REAL;
END_VAR
VAR CONSTANT
    REGION_LOW : INT := 0;
    REGION_MIDDLE : INT := 1;
    REGION_HIGH : INT := 2;
END_VAR

StartEdge(CLK := StartCommand);
start := StartEdge.Q;
stop := StopCommand;

h := INT_TO_REAL(LevelMeter) * h_span / INT_TO_REAL(FullScaleValue);
e := h_sp - h;

IF h < h_target THEN
    r := REGION_LOW;
ELSIF h < h_max THEN
    r := REGION_MIDDLE;
ELSE
    r := REGION_HIGH;
END_IF;

WasRegulating := x1;
EnteredRegulation := FALSE;

(* Transition t1. The rising-edge event is consumed even during stop. *)
IF x0 AND start AND NOT stop AND (r <> REGION_HIGH) THEN
    x0 := FALSE;
    x1 := TRUE;
    EnteredRegulation := TRUE;
END_IF;

(* Start timing on entry, with a FALSE completion value on that scan.
   Loss of the tolerance condition resets the continuous hold time. *)
HoldTimer(
    IN := x1 AND (ABS(e) <= eps),
    PT := t_h
);
settled := HoldTimer.Q;

(* Transition t2 is evaluated only for an upstream step active
   before this scan's transitions. *)
IF WasRegulating AND (stop OR settled OR (r = REGION_HIGH)) THEN
    x1 := FALSE;
    x0 := TRUE;

    HoldTimer(IN := FALSE, PT := t_h);
    settled := FALSE;
END_IF;

fill_valve := x1;
discharge_valve := x1;

FillValve := 0;
DischargeValve := 0;

IF fill_valve THEN
    (* Explicit restart policy: zero integral and suppress derivative kick. *)
    IF EnteredRegulation THEN
        IntegralTerm := 0.0;
        PreviousError := e;
    END_IF;

    ProportionalTerm := Kp * e;

    DerivativeTerm := 0.0;
    IF (Td > 0.0) AND (CycleSeconds > 0.0) THEN
        DerivativeTerm :=
            Kp * Td * (e - PreviousError) / CycleSeconds;
    END_IF;

    TrialIntegral := IntegralTerm;
    IF (Ti > 0.0) AND (CycleSeconds > 0.0) THEN
        TrialIntegral :=
            IntegralTerm + Kp * e * CycleSeconds / Ti;
    END_IF;

    TrialDemand := ProportionalTerm + TrialIntegral + DerivativeTerm;

    (* Suspend integration whenever the proposed output is clamped. *)
    IF (TrialDemand >= 0.0) AND (TrialDemand <= 100.0) THEN
        IntegralTerm := TrialIntegral;
    END_IF;

    Demand := ProportionalTerm + IntegralTerm + DerivativeTerm;

    IF Demand < 0.0 THEN
        LimitedDemand := 0.0;
    ELSIF Demand > 100.0 THEN
        LimitedDemand := 100.0;
    ELSE
        LimitedDemand := Demand;
    END_IF;

    FillValve :=
        REAL_TO_INT(LimitedDemand * INT_TO_REAL(FullScaleValue) / 100.0);

    PreviousError := e;
ELSE
    IntegralTerm := 0.0;
    PreviousError := e;
    LimitedDemand := 0.0;
END_IF;

IF discharge_valve THEN
    DischargeValve := REAL_TO_INT(0.4 * INT_TO_REAL(FullScaleValue));
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
    h_span : REAL := 10.0;
    h_target : REAL := 8.0;
    h_sp : REAL := 8.0;
    h_max : REAL := 9.0;
    eps : REAL := 0.2;
    t_h : TIME := T#10s;
    CycleSeconds : REAL := 0.02;
END_VAR
VAR
    Controller : LevelControlRuntime;

    (* Commissioning defaults; tune for the simulated plant.
       Kp is expressed in percent opening per level unit;
       Ti and Td are expressed in seconds. *)
    Kp : REAL := 20.0;
    Ti : REAL := 5.0;
    Td : REAL := 0.0;
END_VAR

Controller(
    StartCommand := StartCommand,
    StopCommand := StopCommand,
    LevelMeter := LevelMeter,
    FullScaleValue := FULL_SCALE,
    h_span := h_span,
    h_target := h_target,
    h_sp := h_sp,
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

END_PROGRAM


CONFIGURATION Config0
    RESOURCE Res0 ON PLC
        TASK ControlTask(INTERVAL := T#20ms, PRIORITY := 0);
        PROGRAM MainInstance WITH ControlTask : Main;
    END_RESOURCE
END_CONFIGURATION
