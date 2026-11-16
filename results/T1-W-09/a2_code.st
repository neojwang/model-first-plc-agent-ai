FUNCTION_BLOCK TransferController
VAR_INPUT
    sensor_a : BOOL;
    sensor_b : BOOL;
END_VAR
VAR_OUTPUT
    conveyor : BOOL;
END_VAR
VAR
    command_latch : RS;
    x0 : BOOL := TRUE;
    x1 : BOOL := FALSE;
    t1 : BOOL;
    t2 : BOOL;
END_VAR

t1 := x0 AND sensor_a AND NOT sensor_b;
t2 := x1 AND sensor_b;

command_latch(S := t1, R1 := t2);

x1 := command_latch.Q1;
x0 := NOT x1;
conveyor := x1;

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

controller(
    sensor_a := sensor_a,
    sensor_b := sensor_b
);

conveyor := controller.conveyor;

END_PROGRAM
