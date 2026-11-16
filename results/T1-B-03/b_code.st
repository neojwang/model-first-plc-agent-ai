FUNCTION_BLOCK FB_ConveyorControl
VAR_INPUT
    sensor_a : BOOL;
    sensor_b : BOOL;
END_VAR
VAR_OUTPUT
    conveyor : BOOL := FALSE;
END_VAR
VAR
    conveyor_latch : RS;
END_VAR

(* Reset dominates: stop whenever sensor B detects a box. *)
conveyor_latch(S := sensor_a, R1 := sensor_b);
conveyor := conveyor_latch.Q1;

END_FUNCTION_BLOCK


PROGRAM Main
VAR
    SensorA AT %IX100.0 : BOOL;
    SensorB AT %IX100.1 : BOOL;
    conveyor AT %QX100.0 : BOOL;
END_VAR
VAR
    controller : FB_ConveyorControl;
END_VAR

controller(sensor_a := SensorA, sensor_b := SensorB);
conveyor := controller.conveyor;

END_PROGRAM
