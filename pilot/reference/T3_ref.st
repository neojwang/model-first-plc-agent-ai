(* Pilot reference program for task T3 (customized Scene 3, TON and TOF timers).
   For checking the compile script and the scene test before the formal run only:
   not a sample of RQ1 and not a listing of Section 5.2. *)

FUNCTION_BLOCK FB_TonTofFill
  VAR_INPUT
    start_cmd : BOOL;
    stop_cmd : BOOL;
    lsh : BOOL;
    ton_duration : TIME;
    tof_duration : TIME;
  END_VAR
  VAR_OUTPUT
    fill_valve : BOOL;
    discharge_valve : BOOL;
  END_VAR
  VAR
    start_edge : R_TRIG;
    ton_timer : TON;          (* IN := activity of filling step 21 *)
    tof_timer : TOF;          (* IN := activity of filling step 21; Q stays TRUE for tof_duration after step 21 is left *)
    x0 : BOOL := TRUE;        (* step 0 *)
    x21 : BOOL := FALSE;      (* filling step 21 *)
    x22 : BOOL := FALSE;      (* pause step 22 *)
  END_VAR
  start_edge(CLK := start_cmd);
  ton_timer(IN := x21, PT := ton_duration);
  tof_timer(IN := x21, PT := tof_duration);
  IF stop_cmd THEN
    x0 := TRUE;
    x21 := FALSE;
    x22 := FALSE;
  ELSIF x0 AND start_edge.Q THEN
    x0 := FALSE;
    x21 := TRUE;
  ELSIF x21 AND lsh THEN
    x21 := FALSE;
    x0 := TRUE;
  ELSIF x21 AND ton_timer.Q AND NOT lsh THEN
    x21 := FALSE;
    x22 := TRUE;
  ELSIF x22 AND NOT tof_timer.Q THEN
    x22 := FALSE;
    x21 := TRUE;
  END_IF;
  fill_valve := x21;
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
    TON_Duration : TIME := T#5s;
    TOF_Duration : TIME := T#5s;
    logic : FB_TonTofFill;
  END_VAR
  logic(start_cmd := StartCommand, stop_cmd := StopCommand, lsh := LSH,
        ton_duration := TON_Duration, tof_duration := TOF_Duration);
  FillValve := logic.fill_valve;
  DischargeValve := logic.discharge_valve;
END_PROGRAM
