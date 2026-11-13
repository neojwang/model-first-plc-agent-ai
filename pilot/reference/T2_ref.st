(* Pilot reference program for task T2 (customized Scene 3, simple timer).
   For checking the compile script and the scene test before the formal run only:
   not a sample of RQ1 and not a listing of Section 5.2. *)

FUNCTION_BLOCK FB_SimpleTimerFill
  VAR_INPUT
    start_cmd : BOOL;
    stop_cmd : BOOL;
    lshh : BOOL;
    timer_duration : TIME;
  END_VAR
  VAR_OUTPUT
    fill_valve : BOOL;
    discharge_valve : BOOL;
  END_VAR
  VAR
    start_edge : R_TRIG;      (* start: TRUE only in the scan in which StartCommand is pressed *)
    fill_timer : TON;         (* timer of the filling step, IN := activity of step E1 *)
    x0 : BOOL := TRUE;        (* step 0 *)
    xe1 : BOOL := FALSE;      (* filling step E1 *)
  END_VAR
  start_edge(CLK := start_cmd);
  fill_timer(IN := xe1, PT := timer_duration);
  IF stop_cmd THEN
    x0 := TRUE;
    xe1 := FALSE;
  ELSIF x0 AND start_edge.Q THEN
    x0 := FALSE;
    xe1 := TRUE;
  ELSIF xe1 AND (fill_timer.Q OR lshh) THEN
    xe1 := FALSE;
    x0 := TRUE;
  END_IF;
  fill_valve := xe1;
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
    TimerDuration : TIME := T#15s;  (* scene test (a) T#15s: ends before LSH; (b) T#60s: LSHH ends filling *)
    logic : FB_SimpleTimerFill;
  END_VAR
  logic(start_cmd := StartCommand, stop_cmd := StopCommand, lshh := LSHH, timer_duration := TimerDuration);
  FillValve := logic.fill_valve;
  DischargeValve := logic.discharge_valve;
END_PROGRAM
