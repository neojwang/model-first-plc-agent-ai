#!/usr/bin/env python3
"""Randomized run plan: 4 tasks x 2 conditions x n samples (default n = 30), seed fixed for reproducibility.

  python3 make_run_plan.py [--n 30] [--seed 20261112] > run_plan.csv
Run the generations in the order of run_order; record the outcome columns in the same file (save it as runs.csv).
"""
import csv
import random
import sys

TASKS = [('T1', 'Scene 2 From A to B (Set and Reset)', 'set/reset'),
         ('T2', 'Scene 3 Filling Tank (Timers), customized', 'simple timer'),
         ('T3', 'Scene 3 Filling Tank (Timers), customized', 'TON and TOF'),
         ('T4', 'Level Control', 'PID')]
COLS = ['run_order', 'run_id', 'task_id', 'scene', 'strategy', 'condition', 'sample_id', 'model', 'model_version',
        'temperature', 'run_date', 'compiled', 'scene_test_pass', 'a2_grafcet_consistent', 'a2_compiled',
        'a2_scene_test_pass', 'a2_accept', 'nusmv_all_hold', 'nusmv_failed_specs', 'nusmv_tool', 'discrepancy_class',
        'resolution',
        'a1_idef0', 'a1_grafcet_json', 'st_code', 'a2_idef0', 'a2_grafcet_json', 'a2_st_code', 'compile_log',
        'test_log', 'notes']


def main(n, seed):
    rows = []
    for tid, scene, strat in TASKS:
        for cond in ('workflow', 'baseline'):
            for k in range(1, n + 1):
                rid = '%s-%s-%02d' % (tid, 'W' if cond == 'workflow' else 'B', k)
                r = {c: '' for c in COLS}
                r.update(run_id=rid, task_id=tid, scene=scene, strategy=strat, condition=cond, sample_id=k)
                if cond == 'workflow':
                    r.update(a1_idef0='%s/a1_idef0.md' % rid, a1_grafcet_json='%s/a1_grafcet.json' % rid,
                             st_code='%s/a1_code.st' % rid, a2_idef0='%s/a2_idef0.md' % rid,
                             a2_grafcet_json='%s/a2_grafcet.json' % rid, a2_st_code='%s/a2_code.st' % rid)
                else:
                    r.update(st_code='%s/b_code.st' % rid)
                    for c in ('a2_grafcet_consistent', 'a2_compiled', 'a2_scene_test_pass', 'a2_accept',
                              'nusmv_all_hold', 'nusmv_failed_specs', 'nusmv_tool'):
                        r[c] = 'NA'
                if tid == 'T1':
                    r['nusmv_all_hold'], r['nusmv_failed_specs'], r['nusmv_tool'] = 'NA', 'NA', 'NA'
                r.update(compile_log='%s/compile.log' % rid, test_log='%s/test.log' % rid)
                rows.append(r)
    random.Random(seed).shuffle(rows)
    for i, r in enumerate(rows, 1):
        r['run_order'] = i
    w = csv.DictWriter(sys.stdout, fieldnames=COLS)
    w.writeheader()
    w.writerows(rows)


if __name__ == '__main__':
    import argparse
    ap = argparse.ArgumentParser(description='Write the randomized run plan as CSV to standard output.')
    ap.add_argument('--n', type=int, default=30, help='samples per task and condition (default 30)')
    ap.add_argument('--seed', type=int, default=20261112, help='random seed (default 20261112)')
    a = ap.parse_args()
    main(a.n, a.seed)
