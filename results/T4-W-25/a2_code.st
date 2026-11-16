FUNCTION_BLOCK LevelControl
VAR_INPUT
    StartCommand : BOOL;
    StopCommand : BOOL;
    LevelMeter : INT;
    FULL_SCALE : INT := 1000;
    h_span : REAL := 10.0;
    h_sp : REAL := 8.0;
    h_target : REAL := 8.0;
    h_max : REAL := 9.0;
    eps : REAL := 0.2;
    t_h : TIME := T#10s;
    Kp : REAL := 10.0;
    Ti : REAL := 10.0;
    Td : REAL := 0.0;
    SampleSeconds : REAL := 0.02;
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
    StateNumber : INT := 0;
    h : REAL;
    ErrorValue : REAL;
    PreviousError : REAL := 0.0;
    IntegralValue : REAL := 0.0;
    IntegralCandidate : REAL;
    ProportionalValue : REAL;
    DerivativeValue : REAL;
    RawDemand : REAL;
    CandidateDemand : REAL;
    BoundedDemand : REAL;
    PidWasActive : BOOL := FALSE;
END_VAR

StartEdge(CLK := StartCommand);
start := StartEdge.Q;
stop := StopCommand;

IF FULL_SCALE > 0 THEN
    h := INT_TO_REAL(LevelMeter) * h_span / INT_TO_REAL(FULL_SCALE);
ELSE
    h := 0.0;
END_IF;

ErrorValue := h_sp - h;

IF h < h_target THEN
    r := 0;
ELSIF h < h_max THEN
    r := 1;
ELSE
    r := 2;
END_IF;

(* Settling is owned by the regulating step and resets outside the band. *)
HoldTimer(
    IN := (StateNumber = 1) AND NOT stop
          AND (ABS(ErrorValue) <= eps),
    PT := t_h
);
settled := HoldTimer.Q;

IF stop THEN
    StateNumber := 0;
ELSE
    CASE StateNumber OF
        0:
            IF start THEN
                StateNumber := 1;
            END_IF;
        1:
            IF settled OR (r = 2) THEN
                StateNumber := 0;
            END_IF;
    ELSE
        StateNumber := 0;
    END_CASE;
END_IF;

(* Prevent an output pulse when starting at or above the overfill limit. *)
IF (StateNumber = 1) AND (r = 2) THEN
    StateNumber := 0;
END_IF;

fill_valve := (StateNumber = 1);
discharge_valve := (StateNumber = 1);

FillValve := 0;
DischargeValve := 0;

IF fill_valve THEN
    (* PID demand is expressed as valve opening in percent.
       Kp units are percent per level unit; Ti and Td are seconds.
       Integration is explicitly frozen during output saturation. *)
    IF NOT PidWasActive THEN
        IntegralValue := 0.0;
        PreviousError := ErrorValue;
    END_IF;

    ProportionalValue := Kp * ErrorValue;
    DerivativeValue := 0.0;

    IF PidWasActive AND (SampleSeconds > 0.0) THEN
        DerivativeValue :=
            Kp * Td * (ErrorValue - PreviousError) / SampleSeconds;
    END_IF;

    IF Ti <= 0.0 THEN
        IntegralValue := 0.0;
    END_IF;

    RawDemand := ProportionalValue + IntegralValue + DerivativeValue;

    IF (Ti > 0.0) AND (SampleSeconds > 0.0)
       AND (RawDemand >= 0.0) AND (RawDemand <= 100.0) THEN
        IntegralCandidate :=
            IntegralValue + Kp * ErrorValue * SampleSeconds / Ti;
        CandidateDemand :=
            ProportionalValue + IntegralCandidate + DerivativeValue;

        IF (CandidateDemand >= 0.0) AND (CandidateDemand <= 100.0) THEN
            IntegralValue := IntegralCandidate;
        END_IF;
    END_IF;

    RawDemand := ProportionalValue + IntegralValue + DerivativeValue;

    IF RawDemand < 0.0 THEN
        BoundedDemand := 0.0;
    ELSIF RawDemand > 100.0 THEN
        BoundedDemand := 100.0;
    ELSE
        BoundedDemand := RawDemand;
    END_IF;

    IF FULL_SCALE > 0 THEN
        FillValve :=
            REAL_TO_INT(BoundedDemand * INT_TO_REAL(FULL_SCALE) / 100.0);
    END_IF;

    PreviousError := ErrorValue;
    PidWasActive := TRUE;
ELSE
    IntegralValue := 0.0;
    PreviousError := ErrorValue;
    PidWasActive := FALSE;
END_IF;

IF discharge_valve AND (FULL_SCALE > 0) THEN
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
END_VAR
VAR
    Controller : LevelControl;
    (* Commission these gains for the actual plant. *)
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
    SampleSeconds := 0.02
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
