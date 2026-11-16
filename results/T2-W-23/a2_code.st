FUNCTION_BLOCK FB_TankFilling
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
    x0 : BOOL := TRUE;
    x1 : BOOL := FALSE;
END_VAR

(* Detect button presses even while stopped or already filling. *)
StartEdge(CLK := StartCommand);
start := StartEdge.Q;
stop := StopCommand;

(* Stop has priority over entry into the filling step. *)
IF stop THEN
    x1 := FALSE;
ELSIF x0 AND start THEN
    x1 := TRUE;
END_IF;

(* Start timing in the same scan that activates the filling step. *)
FillingTimer(IN := x1, PT := TimerDuration);
timer_done := FillingTimer.Q;

IF x1 AND (stop OR timer_done OR LSHH) THEN
    x1 := FALSE;

    (* Reset the step-owned timer immediately on leaving the step. *)
    FillingTimer(IN := FALSE, PT := TimerDuration);
    timer_done := FillingTimer.Q;
END_IF;

x0 := NOT x1;

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
    TankController : FB_TankFilling;
    (* Configurable example preset; adjust before operation. *)
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
