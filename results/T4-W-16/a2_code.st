FUNCTION_BLOCK FB_LevelControl
VAR_INPUT
    StartCommand : BOOL;
    StopCommand : BOOL;
    LevelMeter : INT;
    FullScaleValue : INT := 1000;
    h_span : REAL := 10.0;
    t_h : TIME := T#10s;
    Kp : REAL := 20.0;
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
    r : INT;

    StateNumber : INT := 0;
    x0 : BOOL := TRUE;
    x1 : BOOL := FALSE;
    PreviouslyActive : BOOL := FALSE;

    h : REAL;
    h_sp : REAL;
    h_target : REAL;
    h_max : REAL;
    eps : REAL;
    LevelError : REAL;
    PreviousError : REAL := 0.0;

    IntegralTerm : REAL := 0.0;
    IntegralCandidate : REAL;
    DerivativeTerm : REAL;
    RawDemand : REAL;
    BoundedDemand : REAL;
END_VAR
VAR CONSTANT
    REGION_LOW : INT := 0;
    REGION_MID : INT := 1;
    REGION_HIGH : INT := 2;
END_VAR

(* Kp is expressed in percent opening per volt.
   Ti, Td and CycleSeconds are expressed in seconds.
   Default gains are commissioning values and require plant tuning. *)

StartEdge(CLK := StartCommand);
start := StartEdge.Q;
stop := StopCommand;

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

LevelError := h_sp - h;

IF h < h_target THEN
    r := REGION_LOW;
ELSIF h < h_max THEN
    r := REGION_MID;
ELSE
    r := REGION_HIGH;
END_IF;

(* The timer runs only during uninterrupted residence in the
   tolerance band while regulation is active. *)
HoldTimer(
    IN := (StateNumber = 1)
          AND NOT stop
          AND (r <> REGION_HIGH)
          AND (ABS(LevelError) <= eps),
    PT := t_h
);
settled := HoldTimer.Q;

(* Stop has priority over every normal transition. *)
IF stop THEN
    StateNumber := 0;
ELSE
    CASE StateNumber OF
        0:
            IF start AND (r <> REGION_HIGH) THEN
                StateNumber := 1;
            END_IF;

        1:
            IF settled OR (r = REGION_HIGH) THEN
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

(* Explicit zero defaults prevent retention of analog commands. *)
FillValve := 0;
DischargeValve := 0;
BoundedDemand := 0.0;

IF x1 THEN
    IF NOT PreviouslyActive THEN
        IntegralTerm := 0.0;
        PreviousError := LevelError;
    END_IF;

    DerivativeTerm := 0.0;
    IF CycleSeconds > 0.0 THEN
        DerivativeTerm := Kp * Td
                          * (LevelError - PreviousError)
                          / CycleSeconds;
    END_IF;

    IntegralCandidate := IntegralTerm;
    IF (Ti > 0.0) AND (CycleSeconds > 0.0) THEN
        IntegralCandidate := IntegralTerm
                             + Kp * LevelError
                             * CycleSeconds / Ti;
    END_IF;

    RawDemand := Kp * LevelError
                 + IntegralCandidate
                 + DerivativeTerm;

    (* Conditional integration: reject the integral increment
       whenever the trial controller output requires clamping. *)
    IF RawDemand > 100.0 THEN
        BoundedDemand := 100.0;
    ELSIF RawDemand < 0.0 THEN
        BoundedDemand := 0.0;
    ELSE
        IntegralTerm := IntegralCandidate;
        BoundedDemand := RawDemand;
    END_IF;

    PreviousError := LevelError;

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
    IntegralCandidate := 0.0;
    DerivativeTerm := 0.0;
    RawDemand := 0.0;
    PreviousError := LevelError;
END_IF;

PreviouslyActive := x1;

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
    fill_valve : BOOL;
    discharge_valve : BOOL;

    h_span : REAL := 10.0;
    t_h : TIME := T#10s;
    Kp : REAL := 20.0;
    Ti : REAL := 10.0;
    Td : REAL := 0.0;
END_VAR
VAR CONSTANT
    FULL_SCALE : INT := 1000;
    ScanSeconds : REAL := 0.02;
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
    CycleSeconds := ScanSeconds
);

FillValve := Controller.FillValve;
DischargeValve := Controller.DischargeValve;
fill_valve := Controller.fill_valve;
discharge_valve := Controller.discharge_valve;

END_PROGRAM


CONFIGURATION Config0
    RESOURCE Res0 ON PLC
        TASK ControlTask(INTERVAL := T#20ms, PRIORITY := 0);
        PROGRAM MainInstance WITH ControlTask : Main;
    END_RESOURCE
END_CONFIGURATION
