FUNCTION_BLOCK TankFillingRuntime
VAR_INPUT
    start : BOOL;
    stop : BOOL;
    LSH : BOOL;
    LSHH : BOOL;
    TON_Duration : TIME;
    TOF_Duration : TIME;
END_VAR
VAR_OUTPUT
    fill_valve : BOOL;
    discharge_valve : BOOL;
END_VAR
VAR
    ActiveState : INT := 0;
    FillingTimer : TON;
    PauseTimer : TOF;
    ton_q : BOOL := FALSE;
    tof_q : BOOL := FALSE;
END_VAR

(* Both timers are evaluated on every scan.
   State 0 = x0; state 1 = x1; state 2 = x2. *)
FillingTimer(
    IN := (ActiveState = 1),
    PT := TON_Duration
);

PauseTimer(
    IN := (ActiveState = 1),
    PT := TOF_Duration
);

ton_q := FillingTimer.Q;
tof_q := PauseTimer.Q;

(* Evaluate transitions from the current situation only. *)
CASE ActiveState OF
    0:
        IF start AND NOT stop AND NOT LSH AND NOT LSHH THEN
            ActiveState := 1;
        END_IF;

    1:
        IF stop THEN
            ActiveState := 0;
        ELSIF LSH OR LSHH THEN
            ActiveState := 0;
        ELSIF ton_q THEN
            ActiveState := 2;
        END_IF;

    2:
        IF stop THEN
            ActiveState := 0;
        ELSIF LSH OR LSHH THEN
            ActiveState := 0;
        ELSIF NOT tof_q THEN
            ActiveState := 1;
        END_IF;

ELSE
    ActiveState := 0;
END_CASE;

fill_valve := (ActiveState = 1);
discharge_valve := FALSE;

END_FUNCTION_BLOCK


PROGRAM Main
VAR
    StartCommand AT %IX100.0 : BOOL;
    StopCommand AT %IX100.1 : BOOL;
    LSH AT %IX100.2 : BOOL;
    LSHH AT %IX100.3 : BOOL;
    FillValve AT %QX100.0 : BOOL;
    DischargeValve AT %QX100.1 : BOOL;
END_VAR
VAR
    (* Configurable timer parameters; defaults are five seconds. *)
    TON_Duration : TIME := T#5s;
    TOF_Duration : TIME := T#5s;
    RuntimeInstance : TankFillingRuntime;
    InitializationDone : BOOL := FALSE;
    PreviousStartCommand : BOOL := FALSE;
    start : BOOL := FALSE;
END_VAR

(* Suppress a fictitious start event if the button is held at startup. *)
IF NOT InitializationDone THEN
    PreviousStartCommand := StartCommand;
    InitializationDone := TRUE;
END_IF;

start := StartCommand AND NOT PreviousStartCommand;
PreviousStartCommand := StartCommand;

RuntimeInstance(
    start := start,
    stop := StopCommand,
    LSH := LSH,
    LSHH := LSHH,
    TON_Duration := TON_Duration,
    TOF_Duration := TOF_Duration
);

FillValve := RuntimeInstance.fill_valve;
DischargeValve := RuntimeInstance.discharge_valve;

END_PROGRAM
