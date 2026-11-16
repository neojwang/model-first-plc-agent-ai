FUNCTION_BLOCK FB_Transfer
VAR_INPUT
    sensor_a : BOOL;
    sensor_b : BOOL;
END_VAR
VAR_OUTPUT
    conveyor : BOOL := FALSE;
END_VAR
VAR
    x0 : BOOL := TRUE;
    x1 : BOOL := FALSE;
    t1 : BOOL := FALSE;
    t2 : BOOL := FALSE;
    conveyor_latch : RS;
END_VAR

(* Evaluate transitions from the current GRAFCET situation. *)
t1 := x0 AND sensor_a AND NOT sensor_b;
t2 := x1 AND sensor_b;

(* Retain the running state with a reset-dominant bistable. *)
conveyor_latch(S := t1, R1 := t2);

(* Update the GRAFCET situation and its continuous output. *)
x1 := conveyor_latch.Q1;
x0 := NOT x1;
conveyor := x1;

END_FUNCTION_BLOCK


PROGRAM Main
VAR
    SensorA AT %IX100.0 : BOOL;
    SensorB AT %IX100.1 : BOOL;
    Conveyor AT %QX100.0 : BOOL;
END_VAR
VAR
    transfer_runtime : FB_Transfer;
END_VAR

transfer_runtime(
    sensor_a := SensorA,
    sensor_b := SensorB
);

Conveyor := transfer_runtime.conveyor;

END_PROGRAM
