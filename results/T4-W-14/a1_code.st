FUNCTION_BLOCK LevelControlRuntime
VAR_INPUT
    StartSample : BOOL;
    StopSample : BOOL;
    LevelSample : INT;
    RegisterFullScale : INT := 1000;

    h_sp : REAL := 0.8;
    h_target : REAL := 0.8;
    h_max : REAL := 0.9;
    eps : REAL := 0.02;
    t_h : TIME := T#10s;

    Kp : REAL := 1.0;
    Ti : REAL := 10.0;
    Td : REAL := 0.0;

    (* Must equal the configured cyclic task interval. *)
    CycleTime : TIME := T#20ms;
END_VAR
VAR_OUTPUT
    FillCommand : INT;
    DischargeCommand : INT;
    fill_valve : BOOL;
    discharge_valve : BOOL;
END_VAR
VAR
    StartEdge : R_TRIG;
    HoldTimer : TON;

    start : BOOL;
    stop : BOOL;
    settled : BOOL;

    (* Region encoding avoids reserved identifiers such as MID. *)
    r : INT;

    x0 : BOOL := TRUE;
    x1 : BOOL := FALSE;
    EnteredRegulation : BOOL;

    h : REAL;
    e : REAL;
    InTolerance : BOOL;

    CycleSeconds : REAL;
    IntegralState : REAL := 0.0;
    PreviousError : REAL := 0.0;
    DerivativeTerm : REAL;
    UnboundedDemand : REAL;
    BoundedDemand : REAL;
END_VAR
VAR CONSTANT
    REGION_LOW : INT := 0;
    REGION_MID : INT := 1;
    REGION_HIGH : INT := 2;
END_VAR

StartEdge(CLK := StartSample);
start := StartEdge.Q;
stop := StopSample;

h := INT_TO_REAL(LevelSample) / INT_TO_REAL(RegisterFullScale);
e := h_sp - h;
InTolerance := ABS(e) <= eps;

IF h < h_target THEN
    r := REGION_LOW;
ELSIF h < h_max THEN
    r := REGION_MID;
ELSE
    r := REGION_HIGH;
END_IF;

CycleSeconds := TIME_TO_REAL(CycleTime) / 1000.0;

(* Measure uninterrupted time in tolerance while x1 is active. *)
HoldTimer(IN := x1 AND InTolerance, PT := t_h);
settled := HoldTimer.Q;

EnteredRegulation := FALSE;

(* Evaluate transitions using the situation existing at scan entry.
   ELSIF prevents a second transition in the same evaluation. *)
IF x1 THEN
    IF stop OR settled OR (r = REGION_HIGH) THEN
        x1 := FALSE;
        x0 := TRUE;
    END_IF;
ELSIF x0 THEN
    IF start AND NOT stop AND NOT (r = REGION_HIGH) THEN
        x0 := FALSE;
        x1 := TRUE;
        EnteredRegulation := TRUE;
    END_IF;
END_IF;

IF EnteredRegulation THEN
    IntegralState := 0.0;
    PreviousError := e;

    (* Start the owned timer at activation, not one scan later. *)
    HoldTimer(IN := InTolerance, PT := t_h);
    settled := HoldTimer.Q;
END_IF;

(* Continuous, non-stored GRAFCET actions. *)
fill_valve := x1;
discharge_valve := x1;

IF x1 THEN
    DerivativeTerm := 0.0;

    IF NOT EnteredRegulation AND (CycleSeconds > 0.0) THEN
        DerivativeTerm := Kp * Td * (e - PreviousError) / CycleSeconds;
    END_IF;

    (* PID in normalized valve-opening units.
       IntegralState contains the integral contribution to the output. *)
    UnboundedDemand := Kp * e + IntegralState + DerivativeTerm;

    IF UnboundedDemand > 1.0 THEN
        BoundedDemand := 1.0;
        (* Integration is suspended while the output is clamped. *)
    ELSIF UnboundedDemand < 0.0 THEN
        BoundedDemand := 0.0;
        (* Integration is suspended while the output is clamped. *)
    ELSE
        BoundedDemand := UnboundedDemand;

        (* Update the integral state for the next scan only when
           the current PID output is not clamped.
           A nonpositive Ti disables integral action. *)
        IF (Ti > 0.0) AND (CycleSeconds > 0.0) THEN
            IntegralState := IntegralState
                           + Kp * e * CycleSeconds / Ti;
        END_IF;
    END_IF;

    PreviousError := e;

    FillCommand :=
        REAL_TO_INT(BoundedDemand * INT_TO_REAL(RegisterFullScale));
    DischargeCommand :=
        REAL_TO_INT(0.4 * INT_TO_REAL(RegisterFullScale));
ELSE
    FillCommand := 0;
    DischargeCommand := 0;

    IntegralState := 0.0;
    PreviousError := e;
    DerivativeTerm := 0.0;
    UnboundedDemand := 0.0;
    BoundedDemand := 0.0;

    HoldTimer(IN := FALSE, PT := t_h);
    settled := FALSE;
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
END_VAR
VAR
    Controller : LevelControlRuntime;

    (* Normalized level parameters. *)
    h_sp : REAL := 0.8;
    h_target : REAL := 0.8;
    h_max : REAL := 0.9;
    eps : REAL := 0.02;
    t_h : TIME := T#10s;

    (* Commissioning parameters: Ti and Td are expressed in seconds. *)
    Kp : REAL := 1.0;
    Ti : REAL := 10.0;
    Td : REAL := 0.0;

    (* Configure the OpenPLC cyclic task to this interval. *)
    CycleTime : TIME := T#20ms;

    fill_valve : BOOL;
    discharge_valve : BOOL;
END_VAR

Controller(
    StartSample := StartCommand,
    StopSample := StopCommand,
    LevelSample := LevelMeter,
    RegisterFullScale := FULL_SCALE,
    h_sp := h_sp,
    h_target := h_target,
    h_max := h_max,
    eps := eps,
    t_h := t_h,
    Kp := Kp,
    Ti := Ti,
    Td := Td,
    CycleTime := CycleTime
);

fill_valve := Controller.fill_valve;
discharge_valve := Controller.discharge_valve;

(* Commit outputs only after transition evaluation and action calculation. *)
FillValve := Controller.FillCommand;
DischargeValve := Controller.DischargeCommand;

END_PROGRAM
