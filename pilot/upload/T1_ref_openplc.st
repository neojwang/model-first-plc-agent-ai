(* Pilot reference program for task T1 (Factory I/O Scene 2, From A to B).
   For checking the compile script and the scene test before the formal run only:
   not a sample of RQ1 and not a listing of Section 5.2. *)

FUNCTION_BLOCK FB_FromAtoB
  VAR_INPUT
    sensor_a : BOOL;
    sensor_b : BOOL;
  END_VAR
  VAR_OUTPUT
    conveyor : BOOL;
  END_VAR
  VAR
    run_latch : RS;  (* reset dominant: a box at sensor B keeps the conveyor stopped *)
  END_VAR
  run_latch(S := sensor_a, R1 := sensor_b);
  conveyor := run_latch.Q1;
END_FUNCTION_BLOCK

PROGRAM Main
  VAR
    SensorA AT %IX100.0 : BOOL;
    SensorB AT %IX100.1 : BOOL;
    Conveyor AT %QX100.0 : BOOL;
  END_VAR
  VAR
    logic : FB_FromAtoB;
  END_VAR
  logic(sensor_a := SensorA, sensor_b := SensorB);
  Conveyor := logic.conveyor;
END_PROGRAM

(* Configuration appended by compile_check.py: the only change to the generated code. *)
CONFIGURATION Config0
  RESOURCE Res0 ON PLC
    TASK TaskMain(INTERVAL := T#20ms, PRIORITY := 0);
    PROGRAM Inst0 WITH TaskMain : Main;
  END_RESOURCE
END_CONFIGURATION
