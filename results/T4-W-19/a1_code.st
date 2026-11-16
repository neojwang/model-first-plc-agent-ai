FUNCTION_BLOCK LevelControlRuntime
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

    x0 : BOOL := TRUE;
    x1 : BOOL := FALSE;
    WasRegulating : BOOL;
    EnteringRegulation : BOOL;

    h : REAL;
    e : REAL;
    PreviousError : REAL := 0.0;
    IntegralTerm : REAL := 0.0;
    ProportionalTerm : REAL;
    DerivativeTerm : REAL;
    UnclampedDemand : REAL;
    BoundedDemand : REAL;
END_VAR
VAR CONSTANT
    REGION_LOW : INT := 0;
    REGION_MIDDLE : INT := 1;
    REGION_HIGH : INT := 2;
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

WasRegulating := x1;

(* The hold condition requires uninterrupted in-band operation. *)
HoldTimer(
    IN := x1 AND NOT stop AND (ABS(e) <= eps),
    PT := t_h
);
settled := HoldTimer.Q;

(* Evaluate transitions using the situation at the start of this scan. *)
IF x0 THEN
    IF start AND NOT stop AND (r <> REGION_HIGH) THEN
        x0 := FALSE;
        x1 := TRUE;
    END_IF;
ELSIF x1 THEN
    IF stop OR settled OR (r = REGION_HIGH) THEN
        x0 := TRUE;
        x1 := FALSE;
    END_IF;
ELSE
    x0 := TRUE;
    x1 := FALSE;
END_IF;

EnteringRegulation := x1 AND NOT WasRegulating;

(* Start the timer on entry and clear it immediately on exit. *)
IF EnteringRegulation THEN
    HoldTimer(IN := (ABS(e) <= eps), PT := t_h);
    settled := FALSE;
ELSIF NOT x1 THEN
    HoldTimer(IN := FALSE, PT := t_h);
    settled := FALSE;
END_IF;

fill_valve := x1;
discharge_valve := x1;

FillValve := 0;
DischargeValve := 0;

IF fill_valve THEN
    (* Initialize each run without derivative kick or retained integral. *)
    IF EnteringRegulation THEN
        IntegralTerm := 0.0;
        PreviousError := e;
    END_IF;

    ProportionalTerm := Kp * e;
    DerivativeTerm := 0.0;

    IF (Td > 0.0) AND (CycleSeconds > 0.0) THEN
        DerivativeTerm :=
            Kp * Td * (e - PreviousError) / CycleSeconds;
    END_IF;

    UnclampedDemand :=
        ProportionalTerm + IntegralTerm + DerivativeTerm;

    (* Demand units are percent of valve opening. *)
    IF UnclampedDemand > 100.0 THEN
        BoundedDemand := 100.0;
    ELSIF UnclampedDemand < 0.0 THEN
        BoundedDemand := 0.0;
    ELSE
        BoundedDemand := UnclampedDemand;

        (* Suspend integration whenever the output is clamped.
           The updated integral contributes on the next scan. *)
        IF (Ti > 0.0) AND (CycleSeconds > 0.0) THEN
            IntegralTerm :=
                IntegralTerm + Kp * e * CycleSeconds / Ti;
        END_IF;
    END_IF;

    PreviousError := e;

    FillValve := REAL_TO_INT(
        BoundedDemand * INT_TO_REAL(FULL_SCALE) / 100.0
    );
ELSE
    IntegralTerm := 0.0;
    PreviousError := e;
    BoundedDemand := 0.0;
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
VAR CONSTANT
    FULL_SCALE : INT := 1000;
    h_span : REAL := 10.0;
    h_sp : REAL := 8.0;
    h_target : REAL := 8.0;
    h_max : REAL := 9.0;
    eps : REAL := 0.2;
    t_h : TIME := T#10s;
    CycleSeconds : REAL := 0.02;
END_VAR
VAR
    Controller : LevelControlRuntime;

    (* Initial tuning values; commission these gains for the plant.
       Kp units: percent opening per level unit; Ti and Td: seconds.
       Ti <= 0 disables integration; Td <= 0 disables differentiation. *)
    Kp : REAL := 10.0;
    Ti : REAL := 10.0;
    Td : REAL := 0.0;
END_VAR

Controller(
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

FillValve := Controller.FillValve;
DischargeValve := Controller.DischargeValve;

END_PROGRAM


CONFIGURATION Config0
    RESOURCE Res0 ON PLC
        TASK MainTask(INTERVAL := T#20ms, PRIORITY := 0);
        PROGRAM MainInstance WITH MainTask : Main;
    END_RESOURCE
END_CONFIGURATION
