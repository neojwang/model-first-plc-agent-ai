FUNCTION_BLOCK TransferRuntime
VAR_INPUT
    sensor_a : BOOL;
    sensor_b : BOOL;
END_VAR
VAR_OUTPUT
    conveyor : BOOL := FALSE;
END_VAR
VAR
    command_latch : RS;
END_VAR

(* Q1 = FALSE represents initial step x0; Q1 = TRUE represents x1. *)
command_latch(
    S := sensor_a AND NOT sensor_b,
    R1 := sensor_b
);

conveyor := command_latch.Q1;

END_FUNCTION_BLOCK


PROGRAM Main
VAR
    SensorA AT %IX100.0 : BOOL;
    SensorB AT %IX100.1 : BOOL;
    Conveyor AT %QX100.0 : BOOL := FALSE;
END_VAR
VAR
    transfer_control : TransferRuntime;
END_VAR

transfer_control(
    sensor_a := SensorA,
    sensor_b := SensorB
);

Conveyor := transfer_control.conveyor;

END_PROGRAM
