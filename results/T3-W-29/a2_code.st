FUNCTION_BLOCK FB_TimedTankFilling
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
    SequenceState : INT := 0;
    FillingActive : BOOL;
    FillingTimer : TON;
    PauseTimer : TOF;
    ton_q : BOOL;
    tof_q : BOOL;
END_VAR

(* Both standard timers measure the activity of the filling step. *)
FillingActive := (SequenceState = 1);

FillingTimer(
    IN := FillingActive,
    PT := TON_Duration
);

PauseTimer(
    IN := FillingActive,
    PT := TOF_Duration
);

ton_q := FillingTimer.Q;
tof_q := PauseTimer.Q;

(* Stop has priority over every normal transition. *)
IF stop THEN
    SequenceState := 0;
ELSE
    CASE SequenceState OF
        0:
            IF start AND NOT LSH THEN
                SequenceState := 1;
            END_IF;

        1:
            IF LSH THEN
                SequenceState := 0;
            ELSIF ton_q THEN
                SequenceState := 2;
            END_IF;

        2:
            IF LSH THEN
                SequenceState := 0;
            ELSIF NOT tof_q THEN
                SequenceState := 1;
            END_IF;

        ELSE
            SequenceState := 0;
    END_CASE;
END_IF;

fill_valve := (SequenceState = 1);
discharge_valve := FALSE;

(* LSHH is available for monitoring; the GRAFCET defines no LSHH trip. *)
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
    (* Example presets; configure these for the plant. *)
    TON_Duration : TIME := T#5s;
    TOF_Duration : TIME := T#5s;
    StartEdge : R_TRIG;
    TankController : FB_TimedTankFilling;
END_VAR

StartEdge(CLK := StartCommand);

TankController(
    start := StartEdge.Q,
    stop := StopCommand,
    LSH := LSH,
    LSHH := LSHH,
    TON_Duration := TON_Duration,
    TOF_Duration := TOF_Duration
);

FillValve := TankController.fill_valve;
DischargeValve := TankController.discharge_valve;

END_PROGRAM
