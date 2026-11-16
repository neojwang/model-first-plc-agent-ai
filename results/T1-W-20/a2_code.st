FUNCTION_BLOCK TransferController
VAR_INPUT
    sensor_a : BOOL;
    sensor_b : BOOL;
END_VAR
VAR_OUTPUT
    conveyor : BOOL;
END_VAR
VAR
    run_latch : RS;
END_VAR

run_latch(S := sensor_a, R1 := sensor_b);
conveyor := run_latch.Q1;

END_FUNCTION_BLOCK


PROGRAM Main
VAR
    sensor_a AT %IX100.0 : BOOL;
    sensor_b AT %IX100.1 : BOOL;
    conveyor AT %QX100.0 : BOOL;
END_VAR
VAR
    controller : TransferController;
END_VAR

controller(sensor_a := sensor_a, sensor_b := sensor_b);
conveyor := controller.conveyor;

END_PROGRAM
