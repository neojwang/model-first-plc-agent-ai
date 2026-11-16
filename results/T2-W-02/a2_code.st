FUNCTION_BLOCK FB_TimedTank
VAR_INPUT
    StartCommand : BOOL;
    StopCommand : BOOL;
    LSH : BOOL;
    LSHH : BOOL;
    TimerDuration : TIME;
END_VAR
VAR_OUTPUT
    fill_valve : BOOL;
    discharge_valve : BOOL;
END_VAR
VAR
    StartEdge : R_TRIG;
    FillingTimer : TON;
    start : BOOL;
    stop : BOOL;
    timer_done : BOOL;
    x1 : BOOL := FALSE;
END_VAR

(* Detect each press, including presses during stop or filling. *)
StartEdge(CLK := StartCommand);
start := StartEdge.Q;
stop := StopCommand;

(* Stop and high-high detection take priority over starting. *)
IF stop OR LSHH THEN
    x1 := FALSE;
ELSIF NOT x1 AND start THEN
    x1 := TRUE;
END_IF;

(* Timing begins in the same scan as entry into the filling step. *)
FillingTimer(IN := x1, PT := TimerDuration);
timer_done := FillingTimer.Q;

IF x1 AND timer_done THEN
    x1 := FALSE;

    (* Reset the owned timer immediately on leaving its step. *)
    FillingTimer(IN := FALSE, PT := TimerDuration);
    timer_done := FillingTimer.Q;
END_IF;

fill_valve := x1;
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
    TankController : FB_TimedTank;
    (* Configurable preset; adjust to the required filling duration. *)
    TimerDuration : TIME := T#10s;
END_VAR

TankController(
    StartCommand := StartCommand,
    StopCommand := StopCommand,
    LSH := LSH,
    LSHH := LSHH,
    TimerDuration := TimerDuration
);

FillValve := TankController.fill_valve;
DischargeValve := TankController.discharge_valve;

END_PROGRAM
