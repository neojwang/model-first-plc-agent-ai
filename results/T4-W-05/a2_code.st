FUNCTION_BLOCK FB_LevelControl
VAR_INPUT
    StartCommand : BOOL;
    StopCommand : BOOL;
    LevelMeter : INT;
    FullScaleValue : INT := 1000;
    h_span : REAL := 10.0;
    t_h : TIME := T#10s;
    Kp : REAL := 20.0;
    Ti : REAL := 5.0;
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
    r : INT;
    SequenceState : INT := 0;
    x0 : BOOL := TRUE;
    x1 : BOOL := FALSE;
    WasRegulating : BOOL := FALSE;

    h : REAL;
    h_sp : REAL;
    h_target : REAL;
    h_max : REAL;
    eps : REAL;
    e : REAL;

    IntegralTerm : REAL := 0.0;
    PreviousError : REAL := 0.0;
    DerivativeTerm : REAL := 0.0;
    RawDemand : REAL := 0.0;
    BoundedDemand : REAL := 0.0;
    EffectiveCycle : REAL;
END_VAR
VAR CONSTANT
    R_LOW : INT := 0;
    R_MID : INT := 1;
    R_HIGH : INT := 2;
END_VAR

StartEdge(CLK := StartCommand);
start := StartEdge.Q;
stop := StopCommand;

EffectiveCycle := CycleSeconds;
IF EffectiveCycle <= 0.0 THEN
    EffectiveCycle := 0.02;
END_IF;

h_sp := 0.8 * h_span;
h_target := h_sp;
h_max := 0.9 * h_span;
eps := 0.02 * h_span;

IF FullScaleValue > 0 THEN
    h := INT_TO_REAL(LevelMeter) * h_span
         / INT_TO_REAL(FullScaleValue);
ELSE
    h := h_max;
END_IF;

e := h_sp - h;

IF h < h_target THEN
    r := R_LOW;
ELSIF h < h_max THEN
    r := R_MID;
ELSE
    r := R_HIGH;
END_IF;

(* Stop takes priority over starting or continuing regulation. *)
IF stop THEN
    SequenceState := 0;
ELSE
    CASE SequenceState OF
        0:
            IF start THEN
                SequenceState := 1;
            END_IF;
        1:
            SequenceState := 1;
    ELSE
        SequenceState := 0;
    END_CASE;
END_IF;

(* The hold interval is continuous and belongs to regulation only. *)
HoldTimer(
    IN := (SequenceState = 1) AND NOT stop AND (ABS(e) <= eps),
    PT := t_h
);
settled := HoldTimer.Q;

IF SequenceState = 1 THEN
    IF stop OR settled OR (r = R_HIGH) THEN
        SequenceState := 0;
    END_IF;
END_IF;

x0 := SequenceState = 0;
x1 := SequenceState = 1;
fill_valve := x1;
discharge_valve := x1;

FillValve := 0;
DischargeValve := 0;

IF x1 THEN
    (* Initialize the PID on entry without a derivative kick. *)
    IF NOT WasRegulating THEN
        IntegralTerm := 0.0;
        PreviousError := e;
    END_IF;

    DerivativeTerm := 0.0;
    IF Td > 0.0 THEN
        DerivativeTerm :=
            Kp * Td * (e - PreviousError) / EffectiveCycle;
    END_IF;

    IF Ti <= 0.0 THEN
        IntegralTerm := 0.0;
    END_IF;

    (* Demand is expressed in percent; error is expressed in volts. *)
    RawDemand := Kp * e + IntegralTerm + DerivativeTerm;

    IF RawDemand > 100.0 THEN
        BoundedDemand := 100.0;
    ELSIF RawDemand < 0.0 THEN
        BoundedDemand := 0.0;
    ELSE
        BoundedDemand := RawDemand;

        (* Suspend integration whenever the output is clamped. *)
        IF Ti > 0.0 THEN
            IntegralTerm :=
                IntegralTerm + Kp * e * EffectiveCycle / Ti;
        END_IF;
    END_IF;

    PreviousError := e;

    IF FullScaleValue > 0 THEN
        FillValve := REAL_TO_INT(
            BoundedDemand * INT_TO_REAL(FullScaleValue) / 100.0
        );
        DischargeValve := REAL_TO_INT(
            0.4 * INT_TO_REAL(FullScaleValue)
        );
    END_IF;
ELSE
    IntegralTerm := 0.0;
    PreviousError := e;
    DerivativeTerm := 0.0;
    RawDemand := 0.0;
    BoundedDemand := 0.0;

    (* Clear the owned hold condition immediately on leaving regulation. *)
    HoldTimer(IN := FALSE, PT := t_h);
    settled := FALSE;
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
    Kp : REAL := 20.0;
    Ti : REAL := 5.0;
    Td : REAL := 0.0;
END_VAR
VAR CONSTANT
    FULL_SCALE : INT := 1000;
    h_span : REAL := 10.0;
    t_h : TIME := T#10s;
    CycleSeconds : REAL := 0.02;
END_VAR

Controller(
    StartCommand := StartCommand,
    StopCommand := StopCommand,
    LevelMeter := LevelMeter,
    FullScaleValue := FULL_SCALE,
    h_span := h_span,
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
