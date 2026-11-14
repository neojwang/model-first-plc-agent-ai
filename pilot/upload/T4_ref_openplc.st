(* Pilot reference program for task T4 (Factory I/O Level Control, PID control).
   For checking the compile script and the scene test before the formal run only:
   not a sample of RQ1 and not a listing of Section 5.2.
   FULL_SCALE = 1000 as in the task card (Factory I/O Modbus TCP/IP Server driver with Scale = 100).
   Kp, Ti and Td come from pilot/pid_pretune.py and are confirmed by the logic analysis in pilot/vc
   (this program compiled and run in closed loop; frequency-domain margins).  They are not tuned in
   Factory I/O (author's ruling, 2026-11-13). *)

FUNCTION_BLOCK FB_LevelPID
  VAR_INPUT
    start_cmd : BOOL;
    stop_cmd : BOOL;
    level_raw : INT;
    full_scale : INT;
    kp : REAL;
    ti : REAL;          (* integral time in s; 0 disables the integral action *)
    td : REAL;          (* derivative time in s *)
    ts : REAL;          (* sampling period in s, equal to the task interval *)
  END_VAR
  VAR_OUTPUT
    fill_cmd : INT;
    discharge_cmd : INT;
  END_VAR
  VAR
    start_edge : R_TRIG;
    hold_timer : TON;   (* settled: |e| <= eps has held for t_h *)
    x0 : BOOL := TRUE;
    xe3 : BOOL := FALSE;
    h : REAL;           (* level as a fraction of the measuring span *)
    e : REAL;
    e_prev : REAL;
    i_term : REAL;
    d_term : REAL;
    u_raw : REAL;
    u : REAL;
    h_sp : REAL := 0.8;
    h_max : REAL := 0.9;
    eps : REAL := 0.02;
    t_h : TIME := T#10s;
    u_d : REAL := 0.4;  (* constant discharge-valve opening *)
  END_VAR
  start_edge(CLK := start_cmd);
  IF full_scale > 0 THEN
    h := INT_TO_REAL(level_raw) / INT_TO_REAL(full_scale);
  ELSE
    h := 0.0;
  END_IF;
  e := h_sp - h;
  hold_timer(IN := xe3 AND (ABS(e) <= eps), PT := t_h);
  IF stop_cmd THEN
    x0 := TRUE;
    xe3 := FALSE;
  ELSIF x0 AND start_edge.Q THEN
    x0 := FALSE;
    xe3 := TRUE;
    i_term := 0.0;
    e_prev := e;
  ELSIF xe3 AND (hold_timer.Q OR (h >= h_max)) THEN
    xe3 := FALSE;
    x0 := TRUE;
  END_IF;
  IF xe3 THEN
    d_term := 0.0;
    IF ts > 0.0 THEN
      d_term := kp * td * (e - e_prev) / ts;
    END_IF;
    u_raw := kp * e + i_term + d_term;
    IF u_raw > 1.0 THEN
      u := 1.0;                      (* clamped: integration suspended *)
    ELSIF u_raw < 0.0 THEN
      u := 0.0;                      (* clamped: integration suspended *)
    ELSE
      u := u_raw;
      IF ti > 0.0 THEN
        i_term := i_term + kp * ts / ti * e;
      END_IF;
    END_IF;
    e_prev := e;
    fill_cmd := REAL_TO_INT(u * INT_TO_REAL(full_scale));
    discharge_cmd := REAL_TO_INT(u_d * INT_TO_REAL(full_scale));
  ELSE
    u := 0.0;
    fill_cmd := 0;
    discharge_cmd := 0;
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
  VAR
    FULL_SCALE : INT := 1000;   (* register value at 10 V: driver Scale = 100, see the task card *)
    Kp : REAL := 5.0;           (* pid_pretune.py; confirmed by pilot/vc *)
    Ti : REAL := 40.0;
    Td : REAL := 0.0;
    Ts : REAL := 0.02;          (* equals the 20 ms task interval of the compile script *)
    ctrl : FB_LevelPID;
  END_VAR
  ctrl(start_cmd := StartCommand, stop_cmd := StopCommand, level_raw := LevelMeter,
       full_scale := FULL_SCALE, kp := Kp, ti := Ti, td := Td, ts := Ts);
  FillValve := ctrl.fill_cmd;
  DischargeValve := ctrl.discharge_cmd;
END_PROGRAM

(* Configuration appended by compile_check.py: the only change to the generated code. *)
CONFIGURATION Config0
  RESOURCE Res0 ON PLC
    TASK TaskMain(INTERVAL := T#20ms, PRIORITY := 0);
    PROGRAM Inst0 WITH TaskMain : Main;
  END_RESOURCE
END_CONFIGURATION
