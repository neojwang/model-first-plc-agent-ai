FUNCTION_BLOCK LevelControl
VAR_INPUT
    StartCommand : BOOL;
    StopCommand : BOOL;
    LevelMeter : INT;
    FULL_SCALE : INT;
    h_span : REAL;
    Kp : REAL;
    Ti : REAL;
    Td : REAL;
END_VAR
VAR_OUTPUT
    fill_valve : BOOL;
    discharge_valve : BOOL;
    FillDemand : INT;
    DischargeDemand : INT;
END_VAR
VAR
    StartEdge : R_TRIG;
    HoldTimer : TON;

    start : BOOL;
    stop : BOOL;
    settled : BOOL;

    (* Region encoding: 0 = LOW, 1 = MID, 2 = HIGH.
       MID is a standard function name, so it is not an identifier. *)
    r : INT := 0;
    ControlState : INT := 0;

    h : REAL;
    h_target : REAL;
    h_sp : REAL;
    h_max : REAL;
    eps : REAL;
    e : REAL;
    PreviousError : REAL := 0.0;

    IntegralTerm : REAL := 0.0;
    CandidateIntegral : REAL;
    ProportionalTerm : REAL;
    DerivativeTerm : REAL;
    UnclampedOutput : REAL;
    CandidateOutput : REAL;
    ValvePercent : REAL;
    FirstPidScan : BOOL := TRUE;
END_VAR
VAR CONSTANT
    CycleSeconds : REAL := 0.02;
    t_h : TIME := T#10s;
END_VAR

StartEdge(CLK := StartCommand);
start := StartEdge.Q;
stop := StopCommand;

h_target := 0.8 * h_span;
h_sp := h_target;
h_max := 0.9 * h_span;
eps := 0.02 * h_span;

IF FULL_SCALE > 0 THEN
    h := INT_TO_REAL(LevelMeter) * h_span / INT_TO_REAL(FULL_SCALE);
ELSE
    h := 0.0;
END_IF;

e := h_sp - h;

IF h < h_target THEN
    r := 0;
ELSIF h < h_max THEN
    r := 1;
ELSE
    r := 2;
END_IF;

IF stop THEN
    ControlState := 0;
ELSIF (ControlState = 0) AND start THEN
    ControlState := 1;
    FirstPidScan := TRUE;
END_IF;

HoldTimer(
    IN := (ControlState = 1)
          AND NOT stop
          AND (r <> 2)
          AND (ABS(e) <= eps),
    PT := t_h
);
settled := HoldTimer.Q;

IF (ControlState = 1) AND (settled OR (r = 2)) THEN
    ControlState := 0;
END_IF;

fill_valve := FALSE;
discharge_valve := FALSE;
FillDemand := 0;
DischargeDemand := 0;

CASE ControlState OF
    0:
        IntegralTerm := 0.0;
        PreviousError := e;
        FirstPidScan := TRUE;
        ValvePercent := 0.0;

    1:
        fill_valve := TRUE;
        discharge_valve := TRUE;

        (* Discrete PID: Kp is percent opening per level unit;
           Ti and Td are in seconds. Ti <= 0 disables integration. *)
        ProportionalTerm := Kp * e;

        IF FirstPidScan THEN
            PreviousError := e;
            FirstPidScan := FALSE;
        END_IF;

        DerivativeTerm :=
            Kp * Td * (e - PreviousError) / CycleSeconds;

        UnclampedOutput :=
            ProportionalTerm + IntegralTerm + DerivativeTerm;

        (* Conditional integration: freeze the integrator whenever the
           output is clamped, and reject increments causing saturation. *)
        IF Ti > 0.0 THEN
            IF (UnclampedOutput >= 0.0)
               AND (UnclampedOutput <= 100.0) THEN
                CandidateIntegral :=
                    IntegralTerm + Kp * e * CycleSeconds / Ti;
                CandidateOutput :=
                    ProportionalTerm + CandidateIntegral + DerivativeTerm;

                IF (CandidateOutput >= 0.0)
                   AND (CandidateOutput <= 100.0) THEN
                    IntegralTerm := CandidateIntegral;
                END_IF;
            END_IF;
        ELSE
            IntegralTerm := 0.0;
        END_IF;

        UnclampedOutput :=
            ProportionalTerm + IntegralTerm + DerivativeTerm;

        IF UnclampedOutput > 100.0 THEN
            ValvePercent := 100.0;
        ELSIF UnclampedOutput < 0.0 THEN
            ValvePercent := 0.0;
        ELSE
            ValvePercent := UnclampedOutput;
        END_IF;

        PreviousError := e;

        IF FULL_SCALE > 0 THEN
            FillDemand := REAL_TO_INT(
                ValvePercent * INT_TO_REAL(FULL_SCALE) / 100.0
            );
            DischargeDemand := REAL_TO_INT(
                0.4 * INT_TO_REAL(FULL_SCALE)
            );
        END_IF;

ELSE
    ControlState := 0;
    IntegralTerm := 0.0;
    FirstPidScan := TRUE;
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
    Controller : LevelControl;
    h_span : REAL := 10.0;
    Kp : REAL := 25.0;
    Ti : REAL := 5.0;
    Td : REAL := 0.0;
END_VAR

Controller(
    StartCommand := StartCommand,
    StopCommand := StopCommand,
    LevelMeter := LevelMeter,
    FULL_SCALE := FULL_SCALE,
    h_span := h_span,
    Kp := Kp,
    Ti := Ti,
    Td := Td
);

FillValve := Controller.FillDemand;
DischargeValve := Controller.DischargeDemand;

END_PROGRAM


CONFIGURATION Config0
    RESOURCE Res0 ON PLC
        TASK ControlTask(INTERVAL := T#20ms, PRIORITY := 0);
        PROGRAM MainInstance WITH ControlTask : Main;
    END_RESOURCE
END_CONFIGURATION
