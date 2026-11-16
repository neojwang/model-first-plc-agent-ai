FUNCTION_BLOCK ConveyorControl
VAR_INPUT
    sensor_a : BOOL;
    sensor_b : BOOL;
END_VAR
VAR_OUTPUT
    conveyor : BOOL;
END_VAR
VAR
    conveyor_latch : RS;
END_VAR

conveyor_latch(
    S := sensor_a AND NOT sensor_b,
    R1 := sensor_b
);
conveyor := conveyor_latch.Q1;

END_FUNCTION_BLOCK

PROGRAM Main
VAR
    sensor_a AT %IX100.0 : BOOL;
    sensor_b AT %IX100.1 : BOOL;
    conveyor AT %QX100.0 : BOOL;
END_VAR
VAR
    controller : ConveyorControl;
END_VAR

controller(
    sensor_a := sensor_a,
    sensor_b := sensor_b
);
conveyor := controller.conveyor;

END_PROGRAM
