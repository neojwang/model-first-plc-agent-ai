FUNCTION_BLOCK FB_LevelControl
VAR_INPUT
    StartCommand : BOOL;
    StopCommand : BOOL;
    LevelMeter : INT;
    ScaleValue : INT;
END_VAR
VAR_OUTPUT
    fill_valve : BOOL;
    discharge_valve : BOOL;
    FillCommand : INT;
    DischargeCommand : INT;
END_VAR
VAR CONSTANT
    h_span : REAL := 10.0;
    Kp : REAL := 25.0;       (* PID output in percent; gain in percent/V. *)
    Ti : REAL := 10.0;       (* Integral time in seconds; <= 0 disables it. *)
    Td : REAL := 0.0;        (* Derivative time in seconds. *)
    t_h : TIME := T#10s;
    CycleSeconds : REAL := 0.1;
END_VAR
VAR
    StartEdge : R_TRIG;
    HoldTimer : TON;

    start : BOOL := FALSE;
    stop : BOOL := FALSE;
    settled : BOOL := FALSE;

    (* Region encoding: 0 = LOW, 1 = MID, 2 = HIGH.
       MID is not declared as an identifier because it is a standard function. *)
    r : INT := 0;

    StateNumber : INT := 0;
    h : REAL := 0.0;
    h_sp : REAL := 0.0;
    h_target : REAL := 0.0;
    h_max : REAL := 0.0;
    eps : REAL := 0.0;
    e : REAL := 0.0;

    IntegralTerm : REAL := 0.0;
    TrialIntegral : REAL := 0.0;
    DerivativeTerm : REAL := 0.0;
    PreviousError : REAL := 0.0;
    PreviousActive : BOOL := FALSE;
    RawPercent : REAL := 0.0;
    OutputPercent : REAL := 0.0;
END_VAR

StartEdge(CLK := StartCommand);
start := StartEdge.Q;
stop := StopCommand;

h_target := 0.8 * h_span;
h_sp := h_target;
h_max := 0.9 * h_span;
eps := 0.02 * h_span;

IF ScaleValue > 0 THEN
    h := INT_TO_REAL(LevelMeter) * h_span / INT_TO_REAL(ScaleValue);
ELSE
    h := 0.0;
END_IF;

e := h_sp - h;

IF h < h_target THEN
    r := 0;                 (* LOW *)
ELSIF h < h_max THEN
    r := 1;                 (* MID *)
ELSE
    r := 2;                 (* HIGH *)
END_IF;

(* Stop has priority over a new start. *)
IF stop THEN
    StateNumber := 0;
ELSIF (StateNumber = 0) AND start THEN
    StateNumber := 1;
END_IF;

HoldTimer(
    IN := (StateNumber = 1) AND NOT stop AND (ABS(e) <= eps),
    PT := t_h
);
settled := HoldTimer.Q;

IF (StateNumber = 1) AND (settled OR (r = 2)) THEN
    StateNumber := 0;
END_IF;

fill_valve := FALSE;
discharge_valve := FALSE;
FillCommand := 0;
DischargeCommand := 0;

CASE StateNumber OF
    0:
        IntegralTerm := 0.0;
        TrialIntegral := 0.0;
        DerivativeTerm := 0.0;
        RawPercent := 0.0;
        OutputPercent := 0.0;
        PreviousError := e;
        PreviousActive := FALSE;

    1:
        fill_valve := TRUE;
        discharge_valve := TRUE;

        (* Suppress derivative kick on the first active scan. *)
        IF PreviousActive THEN
            DerivativeTerm :=
                Kp * Td * (e - PreviousError) / CycleSeconds;
        ELSE
            DerivativeTerm := 0.0;
        END_IF;

        TrialIntegral := IntegralTerm;
        IF Ti > 0.0 THEN
            TrialIntegral :=
                IntegralTerm + Kp * e * CycleSeconds / Ti;
        ELSE
            IntegralTerm := 0.0;
            TrialIntegral := 0.0;
        END_IF;

        RawPercent := Kp * e + TrialIntegral + DerivativeTerm;

        (* Conditional integration: reject the integral update whenever
           the trial PID output requires clamping. *)
        IF RawPercent > 100.0 THEN
            OutputPercent := 100.0;
        ELSIF RawPercent < 0.0 THEN
            OutputPercent := 0.0;
        ELSE
            OutputPercent := RawPercent;
            IntegralTerm := TrialIntegral;
        END_IF;

        IF ScaleValue > 0 THEN
            FillCommand := REAL_TO_INT(
                OutputPercent * INT_TO_REAL(ScaleValue) / 100.0
            );
            DischargeCommand := REAL_TO_INT(
                0.4 * INT_TO_REAL(ScaleValue)
            );
        END_IF;

        PreviousError := e;
        PreviousActive := TRUE;

ELSE
    StateNumber := 0;
    IntegralTerm := 0.0;
    PreviousActive := FALSE;
END_CASE;

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
END_VAR

Controller(
    StartCommand := StartCommand,
    StopCommand := StopCommand,
    LevelMeter := LevelMeter,
    ScaleValue := FULL_SCALE
);

FillValve := 0;
DischargeValve := 0;

IF NOT StopCommand THEN
    IF Controller.fill_valve THEN
        FillValve := Controller.FillCommand;
    END_IF;

    IF Controller.discharge_valve THEN
        DischargeValve := Controller.DischargeCommand;
    END_IF;
END_IF;

END_PROGRAM


CONFIGURATION Config0
RESOURCE Res0 ON PLC
    (* Must match CycleSeconds in FB_LevelControl. *)
    TASK ControlTask(INTERVAL := T#100ms, PRIORITY := 0);
    PROGRAM MainInstance WITH ControlTask : Main;
END_RESOURCE
END_CONFIGURATION
