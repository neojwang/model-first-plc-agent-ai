FUNCTION_BLOCK TankFillingControl
VAR_INPUT
    StartCommand : BOOL;
    StopCommand : BOOL;
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
    CycleState : INT := 0;
    StartEdge : R_TRIG;
    FillingTimer : TON;
    PauseTimer : TOF;
    start : BOOL;
    stop : BOOL;
    ton_q : BOOL;
    tof_q : BOOL;
    FillingActive : BOOL;
END_VAR

(* Generate the one-scan start event, including while stopped. *)
StartEdge(CLK := StartCommand);
start := StartEdge.Q;
stop := StopCommand;

(* Both standard timers measure the activity of the filling step.
   The TOF output remains TRUE after that activity ends. *)
FillingActive := (CycleState = 1);
FillingTimer(IN := FillingActive, PT := TON_Duration);
PauseTimer(IN := FillingActive, PT := TOF_Duration);
ton_q := FillingTimer.Q;
tof_q := PauseTimer.Q;

(* Stop has priority over every cycle transition. *)
IF stop THEN
    CycleState := 0;
ELSE
    CASE CycleState OF
        0:
            IF start AND NOT LSH THEN
                CycleState := 1;
            END_IF;

        1:
            IF LSH THEN
                CycleState := 0;
            ELSIF ton_q THEN
                CycleState := 2;
            END_IF;

        2:
            IF LSH THEN
                CycleState := 0;
            ELSIF NOT tof_q THEN
                CycleState := 1;
            END_IF;

    ELSE
        CycleState := 0;
    END_CASE;
END_IF;

fill_valve := (CycleState = 1);
discharge_valve := FALSE;

(* LSHH is monitored through the input interface. The specified
   GRAFCET defines no additional transition or recovery for LSHH. *)
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
    Controller : TankFillingControl;
    (* Adjustable commissioning defaults. *)
    TON_Duration : TIME := T#5s;
    TOF_Duration : TIME := T#5s;
END_VAR

Controller(
    StartCommand := StartCommand,
    StopCommand := StopCommand,
    LSH := LSH,
    LSHH := LSHH,
    TON_Duration := TON_Duration,
    TOF_Duration := TOF_Duration
);

FillValve := Controller.fill_valve;
DischargeValve := Controller.discharge_valve;
END_PROGRAM
