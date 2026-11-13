"""Input and output vocabulary of the four tasks (task cards in prompts/tasks), shared by the scoring scripts.

start is the event of pressing StartCommand: in the model checker it is valid only in the first evolution of a
transient run (Mross et al., ETFA 2023, Sec. III B).
"""

LEVEL = ['LOW', 'MID', 'HIGH']
TASK_IO = {
    'T1': {'inputs': {'sensor_a': 'boolean', 'sensor_b': 'boolean'},
           'derived': {}, 'outputs': ['conveyor']},
    'T2': {'inputs': {'start': 'boolean', 'stop': 'boolean', 'r': LEVEL, 'timer_done': 'boolean'},
           'derived': {'LSH': 'r = MID | r = HIGH', 'LSHH': 'r = HIGH'}, 'outputs': ['fill_valve', 'discharge_valve'],
           'events': ['start']},
    'T3': {'inputs': {'start': 'boolean', 'stop': 'boolean', 'r': LEVEL, 'ton_q': 'boolean', 'tof_q': 'boolean'},
           'derived': {'LSH': 'r = MID | r = HIGH', 'LSHH': 'r = HIGH'}, 'outputs': ['fill_valve', 'discharge_valve'],
           'events': ['start']},
    'T4': {'inputs': {'start': 'boolean', 'stop': 'boolean', 'r': LEVEL, 'settled': 'boolean'},
           'derived': {}, 'outputs': ['fill_valve', 'discharge_valve'], 'events': ['start']},
}
TANK_TASKS = ('T2', 'T3', 'T4')
