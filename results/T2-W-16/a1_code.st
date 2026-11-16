FUNCTION_BLOCK FillingRuntime
VAR_INPUT
    start : BOOL;
    stop : BOOL;
    LSH : BOOL;
    LSHH : BOOL;
    TimerDuration : TIME;
END_VAR
VAR_OUTPUT
    fill_valve : BOOL;
    discharge_valve : BOOL;
END_VAR
VAR
    ActiveState : INT := 0;
    PreviousState : INT := 0;
    FillingTimer : TON;
    timer_done : BOOL := FALSE;
END_VAR

(* Evaluate the timer owned by x1. *)
FillingTimer(IN := (ActiveState = 1), PT := TimerDuration);
timer_done := FillingTimer.Q;

PreviousState := ActiveState;

(* Evaluate transitions from the current situation only. *)
CASE ActiveState OF
    0:
        IF start AND NOT stop AND NOT LSHH THEN
            ActiveState := 1;
        END_IF;

    1:
        IF stop OR LSHH OR timer_done THEN
            ActiveState := 0;
        END_IF;

ELSE
    ActiveState := 0;
END_CASE;

(* Start timing on entry to x1 and reset timing on departure. *)
IF ActiveState <> PreviousState THEN
    FillingTimer(IN := (ActiveState = 1), PT := TimerDuration);
    timer_done := FillingTimer.Q;
END_IF;

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
    (* Configurable filling-time parameter. *)
    TimerDuration : TIME := T#10s;
    StartEdge : R_TRIG;
    Runtime : FillingRuntime;
END_VAR

StartEdge(CLK := StartCommand);

Runtime(
    start := StartEdge.Q,
    stop := StopCommand,
    LSH := LSH,
    LSHH := LSHH,
    TimerDuration := TimerDuration
);

FillValve := Runtime.fill_valve;
DischargeValve := Runtime.discharge_valve;

END_PROGRAM
