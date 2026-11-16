FUNCTION_BLOCK FillingRuntime
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
    x0 : BOOL := TRUE;
    x1 : BOOL := FALSE;
    x2 : BOOL := FALSE;
    t1 : BOOL;
    t2 : BOOL;
    t3 : BOOL;
    t4 : BOOL;
    t5 : BOOL;
    ton_q : BOOL;
    tof_q : BOOL;
    FillingTON : TON;
    FillingTOF : TOF;
END_VAR

(* Evaluate both timers from the current filling-step activity.
   TOF remains TRUE during the off-delay following departure from x1. *)
FillingTON(IN := x1, PT := TON_Duration);
FillingTOF(IN := x1, PT := TOF_Duration);

ton_q := FillingTON.Q;
tof_q := FillingTOF.Q;

(* Evaluate every transition before changing any step activity. *)
t1 := x0 AND start AND NOT stop AND NOT LSH AND NOT LSHH;
t2 := x1 AND ton_q AND NOT stop AND NOT LSH AND NOT LSHH;
t3 := x2 AND NOT tof_q AND NOT stop AND NOT LSH AND NOT LSHH;
t4 := x1 AND (stop OR LSH OR LSHH);
t5 := x2 AND (stop OR LSH OR LSHH);

(* Apply the simultaneous GRAFCET evolution. *)
x0 := (x0 AND NOT t1) OR t4 OR t5;
x1 := (x1 AND NOT (t2 OR t4)) OR t1 OR t3;
x2 := (x2 AND NOT (t3 OR t5)) OR t2;

(* Continuous, non-stored actions of the resulting situation. *)
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
    (* Example initial presets; adjust to the required operating values. *)
    TON_Duration : TIME := T#5s;
    TOF_Duration : TIME := T#5s;
    StartEdge : R_TRIG;
    TankRuntime : FillingRuntime;
END_VAR

(* Generate the one-scan start event. *)
StartEdge(CLK := StartCommand);

TankRuntime(
    start := StartEdge.Q,
    stop := StopCommand,
    LSH := LSH,
    LSHH := LSHH,
    TON_Duration := TON_Duration,
    TOF_Duration := TOF_Duration
);

FillValve := TankRuntime.fill_valve;
DischargeValve := TankRuntime.discharge_valve;

END_PROGRAM
