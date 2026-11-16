FUNCTION_BLOCK ConveyorRuntime
VAR_INPUT
    sensor_a : BOOL;
    sensor_b : BOOL;
END_VAR
VAR_OUTPUT
    conveyor : BOOL := FALSE;
END_VAR
VAR
    command_memory : RS;
END_VAR

command_memory(
    S := sensor_a AND NOT sensor_b,
    R1 := sensor_b
);

conveyor := command_memory.Q1;

END_FUNCTION_BLOCK


PROGRAM Main
VAR
    SensorA AT %IX100.0 : BOOL;
    SensorB AT %IX100.1 : BOOL;
    Conveyor AT %QX100.0 : BOOL;
END_VAR
VAR
    runtime_logic : ConveyorRuntime;
END_VAR

runtime_logic(
    sensor_a := SensorA,
    sensor_b := SensorB
);

Conveyor := runtime_logic.conveyor;

END_PROGRAM
