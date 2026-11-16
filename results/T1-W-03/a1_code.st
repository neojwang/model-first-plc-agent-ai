FUNCTION_BLOCK FB_TransferRuntime
VAR_INPUT
    sensor_a : BOOL;
    sensor_b : BOOL;
    initialize : BOOL;
END_VAR
VAR_OUTPUT
    conveyor : BOOL := FALSE;
END_VAR
VAR
    run_latch : RS;
END_VAR

IF initialize THEN
    run_latch(S := FALSE, R1 := TRUE);
END_IF;

run_latch(
    S := sensor_a AND NOT sensor_b,
    R1 := sensor_b
);

conveyor := run_latch.Q1;

END_FUNCTION_BLOCK


PROGRAM Main
VAR
    sensor_a AT %IX100.0 : BOOL;
    sensor_b AT %IX100.1 : BOOL;
    conveyor AT %QX100.0 : BOOL;
END_VAR
VAR
    runtime : FB_TransferRuntime;
    first_scan : BOOL := TRUE;
END_VAR

runtime(
    sensor_a := sensor_a,
    sensor_b := sensor_b,
    initialize := first_scan
);

conveyor := runtime.conveyor;
first_scan := FALSE;

END_PROGRAM
