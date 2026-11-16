FUNCTION_BLOCK LevelControl
VAR_INPUT
    StartCommand : BOOL;
    StopCommand : BOOL;
    LevelMeter : INT;
    FULL_SCALE : INT;
    Kp : REAL;
    Ti : REAL;
    Td : REAL;
    CycleSeconds : REAL;
END_VAR
VAR_OUTPUT
    FillValve : INT;
    DischargeValve : INT;
    start : BOOL;
    stop : BOOL;
    settled : BOOL;
    (* r: 0 = LOW, 1 = MID, 2 = HIGH.
       MID is not declared as an identifier because it is reserved. *)
    r : INT;
    fill_valve : BOOL;
    discharge_valve : BOOL;
END_VAR
VAR
    StartEdge : R_TRIG;
    HoldTimer : TON;
    StateNumber : INT := 0;
    h_span : REAL := 10.0;
    h_target : REAL;
    h_sp : REAL;
    h_max : REAL;
    eps : REAL;
    t_h : TIME := T#10s;
    h : REAL;
    e : REAL;
    PreviousError : REAL := 0.0;
    IntegralTerm : REAL := 0.0;
    CandidateIntegral : REAL;
    ProportionalTerm : REAL;
    DerivativeTerm : REAL;
    RawOutput : REAL;
    ValvePercent : REAL;
END_VAR

h_target := 0.8 * h_span;
h_sp := h_target;
h_max := 0.9 * h_span;
eps := 0.02 * h_span;

h := INT_TO_REAL(LevelMeter) * h_span / INT_TO_REAL(FULL_SCALE);
e := h_sp - h;

IF h < h_target THEN
    r := 0; (* LOW *)
ELSIF h < h_max THEN
    r := 1; (* MID *)
ELSE
    r := 2; (* HIGH *)
END_IF;

StartEdge(CLK := StartCommand);
start := StartEdge.Q;
stop := StopCommand;

(* Default outputs implement the idle and stopped conditions. *)
FillValve := 0;
DischargeValve := 0;
fill_valve := FALSE;
discharge_valve := FALSE;

IF stop THEN
    StateNumber := 0;
ELSIF (StateNumber = 0) AND start THEN
    StateNumber := 1;
    IntegralTerm := 0.0;
    PreviousError := e;
END_IF;

HoldTimer(
    IN := (StateNumber = 1) AND NOT stop AND (ABS(e) <= eps),
    PT := t_h
);
settled := HoldTimer.Q;

CASE StateNumber OF
    0:
        IntegralTerm := 0.0;
        PreviousError := e;

    1:
        IF settled OR (r = 2) THEN
            StateNumber := 0;
            IntegralTerm := 0.0;
            PreviousError := e;
        ELSE
            ProportionalTerm := Kp * e;

            DerivativeTerm := 0.0;
            IF (CycleSeconds > 0.0) AND (Td > 0.0) THEN
                DerivativeTerm :=
                    Kp * Td * (e - PreviousError) / CycleSeconds;
            END_IF;

            CandidateIntegral := IntegralTerm;
            IF (Ti > 0.0) AND (CycleSeconds > 0.0) THEN
                CandidateIntegral :=
                    IntegralTerm + Kp * e * CycleSeconds / Ti;
            END_IF;

            RawOutput :=
                ProportionalTerm + CandidateIntegral + DerivativeTerm;

            (* Freeze the integral whenever the proposed output
               requires clamping. Output units are percent opening. *)
            IF RawOutput > 100.0 THEN
                ValvePercent := 100.0;
            ELSIF RawOutput < 0.0 THEN
                ValvePercent := 0.0;
            ELSE
                ValvePercent := RawOutput;
                IntegralTerm := CandidateIntegral;
            END_IF;

            PreviousError := e;

            fill_valve := TRUE;
            discharge_valve := TRUE;
            FillValve := REAL_TO_INT(
                ValvePercent * INT_TO_REAL(FULL_SCALE) / 100.0
            );
            DischargeValve :=
                REAL_TO_INT(0.4 * INT_TO_REAL(FULL_SCALE));
        END_IF;

ELSE
    StateNumber := 0;
    IntegralTerm := 0.0;
    PreviousError := e;
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
    CycleSeconds : REAL := 0.02;
END_VAR
VAR
    (* Initial tuning values; tune for the connected tank.
       Kp: percent opening per volt; Ti and Td: seconds. *)
    Kp : REAL := 25.0;
    Ti : REAL := 10.0;
    Td : REAL := 0.0;
    Controller : LevelControl;
END_VAR

Controller(
    StartCommand := StartCommand,
    StopCommand := StopCommand,
    LevelMeter := LevelMeter,
    FULL_SCALE := FULL_SCALE,
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
