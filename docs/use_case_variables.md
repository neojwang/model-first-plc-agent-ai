# Variables of the three tank use cases

Section 5.2 of the paper refers to this file for the variables of the structured text (ST) programs of the three tank use cases. The first three columns give the descriptive names used in the paper. The column "Task card" gives the identifier, address, or parameter that the task cards in `exec/prompts/tasks/` prescribe for the generated code. *X*<sub>21</sub> denotes the activity of step 21, *h* the water level, *h*<sub>span</sub> the measuring span of the level meter (10 V), and *u*<sub>d</sub> the constant opening of the discharge valve.

## Use case 1: simple timer (task T2, Factory I/O Scene 3)

| Variable/Function | Description | Value/Action | Task card (`T2.md`) |
|---|---|---|---|
| StartCommand | Input signal to initiate filling | TRUE when pressed | `StartCommand AT %IX100.0 : BOOL` |
| StopCommand | Input signal to halt filling | TRUE when pressed | `StopCommand AT %IX100.1 : BOOL` (normally open push button) |
| FillValve | Fill-valve command (digital) | TRUE to fill, FALSE otherwise | `FillValve AT %QX100.0 : BOOL` |
| Timer | Simple timer | Counts up to set duration | a timer instance, for example TON |
| TimerDuration | Duration for filling | Predefined value | `TimerDuration : TIME` |
| LSHH | Capacitive level switch at the overfill limit *h*<sub>max</sub> | TRUE when liquid is detected | `LSHH AT %IX100.3 : BOOL` (2.7 m) |

## Use case 2: TON and TOF timers (task T3, Factory I/O Scene 3)

| Variable/Function | Description | Value/Action | Task card (`T3.md`) |
|---|---|---|---|
| StartCommand | Input signal to initiate filling | TRUE when pressed | `StartCommand AT %IX100.0 : BOOL` |
| StopCommand | Input signal to halt filling | TRUE when pressed | `StopCommand AT %IX100.1 : BOOL` (normally open push button) |
| FillValve | Fill-valve command (digital) | TRUE in step 21, FALSE otherwise | `FillValve AT %QX100.0 : BOOL` |
| TON_Timer | Timer ON function, IN := *X*<sub>21</sub> | Counts up to TON duration | TON instance with IN := activity of the filling step |
| TOF_Timer | Timer OFF function, IN := *X*<sub>21</sub> | Q stays TRUE for TOF_Duration after step 21 is left | TOF instance with the same input |
| TON_Duration | Duration for TON timer | Predefined value | `TON_Duration : TIME` |
| TOF_Duration | Duration for TOF timer | Predefined value | `TOF_Duration : TIME` |
| LSH, LSHH | Capacitive level switches at *h*<sub>target</sub> and *h*<sub>max</sub> | TRUE when liquid is detected | `LSH AT %IX100.2 : BOOL` (2.4 m), `LSHH AT %IX100.3 : BOOL` (2.7 m) |

## Use case 3: PID control (task T4, Factory I/O Level Control)

| Variable/Function | Description | Value/Action | Task card (`T4.md`) |
|---|---|---|---|
| StartCommand | Input signal to initiate filling | TRUE when pressed | `StartCommand AT %IX100.0 : BOOL` |
| StopCommand | Input signal to halt filling | TRUE when pressed | `StopCommand AT %IX100.1 : BOOL` (normally open push button) |
| WaterLevelSensor | Feedback on current water level *h* | Continuous value | `LevelMeter AT %IW100 : INT` (0–10 V; `FULL_SCALE` = 1000) |
| PID_Output | Output from PID controller | Modulates valve position | drives `FillValve AT %QW100 : INT` |
| DischargeValve | Discharge-valve command (analog) | *u*<sub>d</sub> during M3, 0 otherwise | `DischargeValve AT %QW101 : INT` (*u*<sub>d</sub> = 40 %, that is, 4 V) |
| Setpoint | Desired water level | Predefined value | *h*<sub>sp</sub> = *h*<sub>target</sub> = 0.8 *h*<sub>span</sub> |
| PID_Parameters | PID tuning parameters | P, I, D values | *K*<sub>p</sub>, *T*<sub>i</sub>, *T*<sub>d</sub>; the scene tests use *K*<sub>p</sub> = 5, *T*<sub>i</sub> = 40 s, *T*<sub>d</sub> = 0 |
| LevelMax | Overfill limit *h*<sub>max</sub> | Predefined value | *h*<sub>max</sub> = 0.9 *h*<sub>span</sub> |
