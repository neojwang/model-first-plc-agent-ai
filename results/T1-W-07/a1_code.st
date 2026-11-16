FUNCTION_BLOCK ConveyorRuntime
VAR_INPUT
    sensor_a : BOOL;
    sensor_b : BOOL;
    initialize : BOOL;
END_VAR
VAR_OUTPUT
    conveyor : BOOL;
END_VAR
VAR
    command_latch : RS;
END_VAR

IF initialize THEN
    command_latch(S := FALSE, R1 := TRUE);
END_IF;

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
    Conveyor AT %QX100.0 : BOOL;
END_VAR
VAR
    runtime : ConveyorRuntime;
    first_scan : BOOL := TRUE;
END_VAR

runtime(
    sensor_a := SensorA,
    sensor_b := SensorB,
    initialize := first_scan
);

Conveyor := runtime.conveyor;
first_scan := FALSE;

END_PROGRAM
