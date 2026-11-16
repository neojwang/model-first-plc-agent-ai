FUNCTION_BLOCK LevelControlRuntime
VAR_INPUT
    StartCommand : BOOL;
    StopCommand : BOOL;
    LevelMeter : INT;
    FULL_SCALE : INT;
    h_sp : REAL;
    h_max : REAL;
    eps : REAL;
    t_h : TIME;
    Kp : REAL;
    Ti : REAL;
    Td : REAL;
    CycleTime : TIME;
END_VAR
VAR_OUTPUT
    FillValve : INT := 0;
    DischargeValve : INT := 0;
    fill_valve : BOOL := FALSE;
    discharge_valve : BOOL := FALSE;
END_VAR
VAR
    StartEdge : R_TRIG;
    HoldTimer : TON;
    start : BOOL;
    stop : BOOL;
    settled : BOOL := FALSE;

    (* Region encoding: 0 = LOW, 1 = MID, 2 = HIGH. *)
    r : INT := 0;

    (* Initial GRAFCET situation: {x0}. *)
    x0 : BOOL := TRUE;
    x1 : BOOL := FALSE;

    h : REAL;
    e : REAL;
    SampleSeconds : REAL;
    IntegralValue : REAL := 0.0;
    IntegralCandidate : REAL;
    PreviousError : REAL := 0.0;
    DerivativeValue : REAL;
    ProportionalValue : REAL;
    RawDemand : REAL;
    BoundedDemand : REAL;
    PidWasActive : BOOL := FALSE;
END_VAR

StartEdge(CLK := StartCommand);
start := StartEdge.Q;
stop := StopCommand;

h := INT_TO_REAL(LevelMeter) / INT_TO_REAL(FULL_SCALE);
e := h_sp - h;

IF h < h_sp THEN
    r := 0;
ELSIF h < h_max THEN
    r := 1;
ELSE
    r := 2;
END_IF;

(* Qualify continuous residence in the tolerance band during x1. *)
HoldTimer(
    IN := x1 AND (ABS(e) <= eps) AND NOT stop,
    PT := t_h
);
settled := HoldTimer.Q;

(* Evaluate only transitions enabled by the preceding situation. *)
IF x0 THEN
    IF start AND NOT stop AND NOT (r = 2) THEN
        x0 := FALSE;
        x1 := TRUE;
    END_IF;
ELSIF x1 THEN
    IF stop OR settled OR (r = 2) THEN
        x1 := FALSE;
        x0 := TRUE;
    END_IF;
END_IF;

(* Non-stored GRAFCET actions. *)
fill_valve := x1;
discharge_valve := x1;

IF NOT x1 THEN
    HoldTimer(IN := FALSE, PT := t_h);
    settled := FALSE;
END_IF;

FillValve := 0;
DischargeValve := 0;

IF fill_valve THEN
    SampleSeconds := TIME_TO_REAL(CycleTime) / 1000.0;

    (* Reset PID state at each new regulation interval. *)
    IF NOT PidWasActive THEN
        IntegralValue := 0.0;
        PreviousError := e;
    END_IF;

    ProportionalValue := Kp * e;
    DerivativeValue := 0.0;

    IF (SampleSeconds > 0.0) AND (Td > 0.0) THEN
        DerivativeValue :=
            Kp * Td * (e - PreviousError) / SampleSeconds;
    END_IF;

    IntegralCandidate := IntegralValue;
    IF (SampleSeconds > 0.0) AND (Ti > 0.0) THEN
        IntegralCandidate :=
            IntegralValue + Kp * e * SampleSeconds / Ti;
    END_IF;

    RawDemand :=
        ProportionalValue + IntegralCandidate + DerivativeValue;

    (* Reject this scan's integral update if it causes saturation. *)
    IF (RawDemand >= 0.0) AND (RawDemand <= 1.0) THEN
        IntegralValue := IntegralCandidate;
    END_IF;

    RawDemand :=
        ProportionalValue + IntegralValue + DerivativeValue;

    IF RawDemand < 0.0 THEN
        BoundedDemand := 0.0;
    ELSIF RawDemand > 1.0 THEN
        BoundedDemand := 1.0;
    ELSE
        BoundedDemand := RawDemand;
    END_IF;

    FillValve :=
        REAL_TO_INT(BoundedDemand * INT_TO_REAL(FULL_SCALE));
    PreviousError := e;
ELSE
    IntegralValue := 0.0;
    PreviousError := e;
END_IF;

IF discharge_valve THEN
    DischargeValve := REAL_TO_INT(0.4 * INT_TO_REAL(FULL_SCALE));
END_IF;

PidWasActive := fill_valve;

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
    Controller : LevelControlRuntime;

    (* Normalized measuring span: 1.0 corresponds to 10 V. *)
    h_sp : REAL := 0.8;
    h_max : REAL := 0.9;
    eps : REAL := 0.02;
    t_h : TIME := T#10s;

    (* Commissioning parameters; Ti and Td are expressed in seconds. *)
    Kp : REAL := 1.0;
    Ti : REAL := 10.0;
    Td : REAL := 0.0;

    (* Configure the OpenPLC cyclic task to match this period. *)
    CycleTime : TIME := T#20ms;
END_VAR

Controller(
    StartCommand := StartCommand,
    StopCommand := StopCommand,
    LevelMeter := LevelMeter,
    FULL_SCALE := FULL_SCALE,
    h_sp := h_sp,
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

END_PROGRAM
