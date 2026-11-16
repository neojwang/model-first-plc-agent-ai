FUNCTION_BLOCK ConveyorRuntime
VAR_INPUT
    sensor_a : BOOL;
    sensor_b : BOOL;
END_VAR
VAR_OUTPUT
    conveyor : BOOL := FALSE;
END_VAR
VAR
    command_latch : RS;
    x0 : BOOL := TRUE;
    x1 : BOOL := FALSE;
END_VAR

command_latch(
    S := sensor_a AND NOT sensor_b,
    R1 := sensor_b
);

x1 := command_latch.Q1;
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
    runtime : ConveyorRuntime;
    initialized : BOOL := FALSE;
END_VAR

IF NOT initialized THEN
    Conveyor := FALSE;
    initialized := TRUE;
END_IF;

runtime(
    sensor_a := SensorA,
    sensor_b := SensorB
);

Conveyor := runtime.conveyor;

END_PROGRAM
