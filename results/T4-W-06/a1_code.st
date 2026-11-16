FUNCTION_BLOCK TankLevelRuntime
VAR_INPUT
    StartCommand : BOOL;
    StopCommand : BOOL;
    LevelMeter : INT;
    FULL_SCALE : INT := 1000;
    h_span : REAL := 10.0;
    t_h : TIME := T#10s;
    Kp : REAL := 1.0;
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
VAR
    StartEdge : R_TRIG;
    HoldTimer : TON;

    start : BOOL;
    stop : BOOL;
    settled : BOOL;

    (* Region encoding: 0 = LOW, 1 = MID, 2 = HIGH. *)
    r : INT;

    x0 : BOOL := TRUE;
    x1 : BOOL := FALSE;
    WasRegulating : BOOL := FALSE;

    h : REAL;
    h_sp : REAL;
    h_target : REAL;
    h_max : REAL;
    eps : REAL;
    e : REAL;
    NormalizedError : REAL;

    IntegralTerm : REAL := 0.0;
    PreviousError : REAL := 0.0;
    DerivativeTerm : REAL := 0.0;
    RawDemand : REAL := 0.0;
    BoundedDemand : REAL := 0.0;
END_VAR

StartEdge(CLK := StartCommand);
start := StartEdge.Q;
stop := StopCommand;

h_sp := 0.8 * h_span;
h_target := h_sp;
h_max := 0.9 * h_span;
eps := 0.02 * h_span;

h := INT_TO_REAL(LevelMeter) * h_span / INT_TO_REAL(FULL_SCALE);
e := h_sp - h;
NormalizedError := e / h_span;

IF h < h_target THEN
    r := 0;
ELSIF h < h_max THEN
    r := 1;
ELSE
    r := 2;
END_IF;

(* The dwell is continuous and is owned exclusively by x1. *)
HoldTimer(
    IN := x1 AND (ABS(e) <= eps),
    PT := t_h
);
settled := x1 AND HoldTimer.Q;

(* Evaluate transitions against the situation at scan entry.
   ELSIF prevents a newly activated step from transitioning again. *)
IF x0 THEN
    IF start AND NOT stop AND (r <> 2) THEN
        x0 := FALSE;
        x1 := TRUE;
    END_IF;
ELSIF x1 THEN
    IF stop OR settled OR (r = 2) THEN
        x1 := FALSE;
        x0 := TRUE;
    END_IF;
END_IF;

fill_valve := x1;
discharge_valve := x1;

IF fill_valve THEN
    (* Initialize controller history on each activation of x1. *)
    IF NOT WasRegulating THEN
        IntegralTerm := 0.0;
        PreviousError := NormalizedError;
    END_IF;

    DerivativeTerm := 0.0;
    IF CycleSeconds > 0.0 THEN
        DerivativeTerm :=
            Kp * Td * (NormalizedError - PreviousError) / CycleSeconds;
    END_IF;

    (* Parallel PID, with normalized error and fractional valve demand.
       Ti and Td are in seconds. Ti <= 0 disables integration. *)
    RawDemand := Kp * NormalizedError + IntegralTerm + DerivativeTerm;

    IF RawDemand > 1.0 THEN
        BoundedDemand := 1.0;
    ELSIF RawDemand < 0.0 THEN
        BoundedDemand := 0.0;
    ELSE
        BoundedDemand := RawDemand;
    END_IF;

    (* Update the integral for the next sample only when this sample's
       output is not clamped. No integration occurs during saturation. *)
    IF (RawDemand >= 0.0) AND (RawDemand <= 1.0) THEN
        IF (Ti > 0.0) AND (CycleSeconds > 0.0) THEN
            IntegralTerm :=
                IntegralTerm
                + Kp * NormalizedError * CycleSeconds / Ti;
        END_IF;
    END_IF;

    PreviousError := NormalizedError;
    FillValve := REAL_TO_INT(BoundedDemand * INT_TO_REAL(FULL_SCALE));
ELSE
    IntegralTerm := 0.0;
    PreviousError := NormalizedError;
    DerivativeTerm := 0.0;
    RawDemand := 0.0;
    BoundedDemand := 0.0;
    FillValve := 0;
END_IF;

IF discharge_valve THEN
    DischargeValve := REAL_TO_INT(0.4 * INT_TO_REAL(FULL_SCALE));
ELSE
    DischargeValve := 0;
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
    Controller : TankLevelRuntime;

    (* Commissioning parameters: tune PID gains for the plant.
       CycleSeconds must match the configured task period. *)
    h_span : REAL := 10.0;
    t_h : TIME := T#10s;
    Kp : REAL := 1.0;
    Ti : REAL := 10.0;
    Td : REAL := 0.0;
    CycleSeconds : REAL := 0.02;

    fill_valve : BOOL;
    discharge_valve : BOOL;
END_VAR

Controller(
    StartCommand := StartCommand,
    StopCommand := StopCommand,
    LevelMeter := LevelMeter,
    FULL_SCALE := FULL_SCALE,
    h_span := h_span,
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
