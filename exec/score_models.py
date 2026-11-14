#!/usr/bin/env python3
"""Score the GRAFCET models of every workflow sample and fill the model columns of runs.csv.

  python3 score_models.py runs.csv --base ARTIFACT_DIR            # report only
  python3 score_models.py runs.csv --base ARTIFACT_DIR --write    # also update runs.csv (a copy is kept as .bak)

For every workflow row:
  * a2_grafcet_consistent, discrepancy_class: criterion (iii), A1 against A2 GRAFCET (compare_grafcet.py);
  * a2_accept: 1 only when a2_compiled, a2_scene_test_pass and a2_grafcet_consistent are all 1 (left empty while any
    of them is empty);
  * tank tasks T2-T4: nusmv_all_hold, nusmv_failed_specs, nusmv_tool for the A1 GRAFCET.  The task I/O of taskio.py
    and properties P1-P4 of Section 3.2 are added to the model; W5 (every evolution reaches a stable situation) is
    reported as a diagnostic and does not enter the verdict.  A .smv file is written next to the JSON for the formal
    NuSMV run; until NuSMV has been run, the verdict comes from the explicit-state pre-check (nusmv_tool = precheck).
    nusmv/run_nusmv.py --write then runs NuSMV on these files and replaces the three columns (nusmv_tool = NuSMV 2.6.0).
"""
import argparse
import csv
import json
import os
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'nusmv'))
sys.path.insert(0, HERE)
import grafcet2smv as G  # noqa: E402
from compare_grafcet import compare  # noqa: E402
from taskio import TASK_IO, TANK_TASKS  # noqa: E402

SPECS = [
    {'id': 'P1', 'ctl': 'AG (r = HIGH -> AX !fill_valve)'},
    {'id': 'P2', 'ctl': 'AG (stop -> AX (x0 & !fill_valve))'},
    {'id': 'P3', 'ctl': 'AG ((fill_valve & !stop) -> E [ !stop U !fill_valve ])'},
    {'id': 'P4', 'ctl': 'AG (!stop -> E [ !stop U x0 ])'},
]
DIAG = [{'id': 'W5', 'ctl': 'AG stable'}]


def nusmv_spec(task, d, name):
    io = TASK_IO[task]
    steps = [x for g in d['graphs'] for x in g['steps']]
    if 'x0' not in steps:
        raise ValueError('no step x0')
    if 'fill_valve' not in d.get('outputs', {}):
        raise ValueError('no output fill_valve')
    allowed = set(io['inputs']) | set(io['derived']) | set(steps)
    for t in d['transitions']:
        bad = G.names(G.parse(t['guard'])) - allowed
        if bad:
            raise ValueError('unknown identifier in guard: %s' % ', '.join(sorted(bad)))
    for k, v in d.get('owned', {}).items():
        if k not in io['inputs'] or v['step'] not in steps:
            raise ValueError('owned condition %s is not an input or has an unknown step' % k)
    return {'name': name, 'source': 'A1 GRAFCET of sample %s' % name, 'inputs': io['inputs'],
            'derived': io['derived'], 'owned': d.get('owned', {}), 'events': io.get('events', []), 'graphs': d['graphs'],
            'transitions': d['transitions'], 'forcing': d.get('forcing', []), 'outputs': d['outputs'],
            'specs': SPECS + DIAG}


def bit(v):
    return str(v).strip() in ('1', 'true', 'True', 'TRUE')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('runs')
    ap.add_argument('--base', default='.')
    ap.add_argument('--write', action='store_true')
    a = ap.parse_args()
    reader = csv.DictReader(open(a.runs, encoding='utf-8'))
    rows = list(reader)
    fields = list(reader.fieldnames or [])
    if not rows:
        sys.exit('%s has no data rows; enter the samples first (columns: analysis/runs_template.csv)' % a.runs)
    load = lambda rel: json.load(open(os.path.join(a.base, rel), encoding='utf-8'))
    n_cmp = n_chk = 0
    for r in rows:
        if r['condition'] != 'workflow':
            continue
        task = r['task_id']
        try:
            d1 = load(r['a1_grafcet_json'])
        except (OSError, ValueError) as e:
            d1 = None
            r['discrepancy_class'] = r['discrepancy_class'] or 'schema: A1 GRAFCET missing or not JSON (%s)' % type(e).__name__
        try:
            d2 = load(r['a2_grafcet_json'])
        except (OSError, ValueError) as e:
            d2 = None
            r['discrepancy_class'] = r['discrepancy_class'] or 'schema: A2 GRAFCET missing or not JSON (%s)' % type(e).__name__
        if d1 is not None and d2 is not None:
            ok, why = compare(task, d1, d2)
            r['a2_grafcet_consistent'] = '1' if ok else '0'
            if not ok and not r['discrepancy_class']:
                r['discrepancy_class'] = why
            n_cmp += 1
        else:
            r['a2_grafcet_consistent'] = '0'
        parts = [r.get('a2_compiled', ''), r.get('a2_scene_test_pass', ''), r['a2_grafcet_consistent']]
        if all(p.strip() for p in parts):
            r['a2_accept'] = '1' if all(bit(p) for p in parts) else '0'
        if task in TANK_TASKS:
            if r.get('nusmv_tool', '').startswith('NuSMV'):
                continue                                  # formal result already entered (nusmv/run_nusmv.py)
            if d1 is None:
                r['nusmv_all_hold'], r['nusmv_failed_specs'], r['nusmv_tool'] = 'NA', 'unparsable: no A1 GRAFCET', 'precheck'
                continue
            try:
                spec = nusmv_spec(task, d1, r['run_id'])
                smv = os.path.join(a.base, os.path.splitext(r['a1_grafcet_json'])[0] + '.smv')
                open(smv, 'w', encoding='utf-8').write(G.to_smv(spec))
                res = G.check(spec, out=open(os.devnull, 'w'))
            except (ValueError, KeyError, SyntaxError, TypeError, NameError) as e:
                r['nusmv_all_hold'], r['nusmv_failed_specs'], r['nusmv_tool'] = 'NA', 'unparsable: %s' % e, 'precheck'
                continue
            failed = [k for k in ('P1', 'P2', 'P3', 'P4') if not res[k]]
            r['nusmv_all_hold'] = '0' if failed else '1'
            r['nusmv_failed_specs'] = ' '.join(failed + ([] if res['W5'] else ['W5(diagnostic)']))
            r['nusmv_tool'] = 'precheck'
            n_chk += 1
    print('criterion (iii) compared for %d workflow samples; tank-task models pre-checked: %d' % (n_cmp, n_chk))
    if a.write:
        shutil.copyfile(a.runs, a.runs + '.bak')
        w = csv.DictWriter(open(a.runs, 'w', encoding='utf-8', newline=''), fieldnames=fields)
        w.writeheader()
        w.writerows(rows)
        print('updated', a.runs, '(previous version kept as %s.bak)' % a.runs)


if __name__ == '__main__':
    main()
