#!/usr/bin/env python3
"""Logic analysis of the pilot reference programs without Factory I/O (pilot only; not part of the experiment).

Replaces the Factory I/O run of the T1-T4 reference programs (author's ruling, 2026-11-13 06:48) and validates the
public scene simulator exec/scene_sim.py, which since 2026-11-13 07:28 gives scene_test_pass (author's ruling).
Every layer runs on the compiled program, through exec/scene_sim.py (same glue, same scene models):

  L1 syntax       the upload files and their scene-test variants (exec/set_params.py) compile with the pinned matiec;
  L2 logic        properties P1-P4 of the paper (Section 3.2) are checked scan by scan on the compiled code over random
                  input sequences (T2-T4); P3 and P4 by a witness input at the end of a sequence;
  L3 function     the registered situations under the nominal scene model (exec/scene_sim.py), the same situations
                  with the references' own configuration at task intervals of 10 ms and 100 ms (a generated program
                  may bring its own configuration), then a robustness grid wider than the simulator's --sensitivity
                  variants;
  faults          configuration faults (stop button normally closed; driver Scale 1) and seeded faults in the
                  references must fail; the SR variant of T1, which the task card permits, is reported.

  python3 vc_check.py --openplc OPENPLC_V3_DIR --pilot ..
"""
import argparse
import hashlib
import importlib.util
import json
import os
import random
import shutil
import sys
import tempfile

_spec = importlib.util.spec_from_file_location(
    'scene_sim', os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'exec', 'scene_sim.py'))
sim = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(sim)
PLC, Bench, Conveyor, V_CONV = sim.PLC, sim.Bench, sim.Conveyor, sim.V_CONV


def scenario(text, task, case):
    return sim.set_params.set_params(text, sim.set_params.SCENARIOS[(task, case)])[0]


def t1_extra(plc, dist=2.0, box=0.4):
    """Not a registered criterion: a new box at A must not restart the conveyor while a box stands at B."""
    p = Conveyor(dist, box, 0.0)
    b = Bench(plc, p)
    p.place()
    b.run_until(lambda: p.run, 2.0)
    b.run_until(lambda: not p.run, b.t + dist / V_CONV + 5.0)
    p.place()
    restarted = b.run_until(lambda: p.run, b.t + 3.0)
    b.run_until(lambda: False, b.t + 3.0)
    ok = not restarted and not p.run and bool(p.at_b())
    return ok, 'box at B kept, conveyor stayed off' if ok else 'conveyor restarted with a box standing at B'


def properties(plc, task, n_seq=300, n_scan=400, seed=20261113):
    """Direct input image, one random input vector per segment.  P1: level region HIGH -> fill valve off within one
    scan; P2: StopCommand -> all outputs off within one scan; P3 and P4 by a witness input at the end of a sequence."""
    rng = random.Random(seed)
    fails = {'P1': 0, 'P2': 0, 'P3': 0, 'P4': 0}
    checks = {'P1': 0, 'P2': 0, 'P3': 0, 'P4': 0}
    analog = task == 'T4'
    fill = '%QW100' if analog else '%QX100.0'
    dis = '%QW101' if analog else '%QX100.1'

    def apply(start, stop, region):
        plc.set('%IX100.0', start)
        plc.set('%IX100.1', stop)
        if analog:
            plc.set('%IW100', {'LOW': rng.randint(0, 799), 'MID': rng.randint(800, 899), 'HIGH': rng.randint(900, 1000)}[region])
        else:
            plc.set('%IX100.2', region != 'LOW')
            plc.set('%IX100.3', region == 'HIGH')

    for _ in range(n_seq):
        plc.reset()
        k = 0
        while k < n_scan:
            seg = rng.randint(1, 120)
            start = rng.random() < 0.3
            stop = rng.random() < 0.08
            region = rng.choice(['LOW', 'LOW', 'MID', 'HIGH'])
            for j in range(seg):
                apply(start and j < 3, stop, region)
                plc.scan()
                k += 1
                if j >= 1 and region == 'HIGH':                 # reaction within one scan
                    checks['P1'] += 1
                    fails['P1'] += plc.get(fill) != 0
                if j >= 1 and stop:
                    checks['P2'] += 1
                    fails['P2'] += plc.get(fill) != 0 or plc.get(dis) != 0
        # P3: with StopCommand FALSE, an open fill valve can be closed (witness: level region HIGH)
        if plc.get(fill) != 0:
            checks['P3'] += 1
            apply(False, False, 'HIGH'); plc.scan(); plc.scan()
            if plc.get(fill) != 0:
                fails['P3'] += 1
        # P4: with StopCommand FALSE, step 0 is reachable.  Witness: level region HIGH for 12 s (longer than any
        # timer preset), then LOW for 13 s without a start: the outputs must stay 0 (this rules out the pause step,
        # which resumes by itself, and regulation, which keeps the discharge valve open); then a start must open the
        # fill valve, which only step 0 allows.
        checks['P4'] += 1
        for _ in range(600):
            apply(False, False, 'HIGH'); plc.scan()
        quiet = True
        for _ in range(650):
            apply(False, False, 'LOW'); plc.scan()
            quiet &= plc.get(fill) == 0 and plc.get(dis) == 0
        apply(True, False, 'LOW'); plc.scan(); plc.scan()
        if not (quiet and plc.get(fill) != 0):
            fails['P4'] += 1
    return checks, fails


def mutants(src):
    """(task, name, upload text, kind): kind 'fault' must fail a registered check or a property; kind 'allowed' is a
    variant the task card permits (SR instead of RS), reported but not required to fail."""
    out = []

    def sub(task, name, text, old, new, kind='fault'):
        assert text.count(old) == 1, (task, name, old)
        out.append((task, name, text.replace(old, new), kind))
    t1, t2, t3, t4 = src['T1'], src['T2'], src['T3'], src['T4']
    sub('T1', 'M1 set and reset swapped', t1, 'run_latch(S := sensor_a, R1 := sensor_b);', 'run_latch(S := sensor_b, R1 := sensor_a);')
    sub('T1', 'M2 never reset', t1, 'run_latch(S := sensor_a, R1 := sensor_b);', 'run_latch(S := sensor_a, R1 := FALSE);')
    sub('T1', 'M3 set dominant (SR)', t1.replace('run_latch : RS;', 'run_latch : SR;'),
        'run_latch(S := sensor_a, R1 := sensor_b);\n  conveyor := run_latch.Q1;',
        'run_latch(S1 := sensor_a, R := sensor_b);\n  conveyor := run_latch.Q1;', 'allowed')
    sub('T2', 'M1 LSHH ignored', t2, 'ELSIF xe1 AND (fill_timer.Q OR lshh) THEN', 'ELSIF xe1 AND fill_timer.Q THEN')
    sub('T2', 'M2 stop ignored', t2, 'IF stop_cmd THEN', 'IF FALSE THEN')
    sub('T2', 'M3 timer never started', t2, 'fill_timer(IN := xe1, PT := timer_duration);', 'fill_timer(IN := FALSE, PT := timer_duration);')
    sub('T3', 'M1 LSH ignored', t3, 'ELSIF x21 AND lsh THEN', 'ELSIF FALSE THEN')
    sub('T3', 'M2 pause never ends', t3, 'ELSIF x22 AND NOT tof_timer.Q THEN', 'ELSIF FALSE THEN')
    sub('T3', 'M3 stop ignored', t3, 'IF stop_cmd THEN', 'IF FALSE THEN')
    sub('T4', 'M1 no anti-windup', t4, '''      u := 1.0;                      (* clamped: integration suspended *)
    ELSIF u_raw < 0.0 THEN''', '''      u := 1.0;
      i_term := i_term + kp * ts / ti * e;
    ELSIF u_raw < 0.0 THEN''')
    sub('T4', 'M2 overfill limit ignored', t4, 'ELSIF xe3 AND (hold_timer.Q OR (h >= h_max)) THEN', 'ELSIF xe3 AND hold_timer.Q THEN')
    sub('T4', 'M3 stop ignored', t4, 'IF stop_cmd THEN', 'IF FALSE THEN')
    return out


def nominal_suite(text, task, build_cache, openplc):
    """Registered situations (exec/scene_sim.py, nominal model), the T1 extra check, and P1-P4 for the tank tasks."""
    verdict, log, result = sim.test_program(text, task, openplc, build_cache)
    res = {('(%s)' % c if task != 'T1' else 'scene'): s['pass'] for c, s in result['situations'].items()}
    if task == 'T1':
        res['extra'] = t1_extra(PLC(text, openplc, build_cache))[0]
    else:
        checks, fails = properties(PLC(scenario(text, task, 'a'), openplc, build_cache), task, n_seq=60, n_scan=300)
        for k in ('P1', 'P2', 'P3', 'P4'):
            res[k] = fails[k] == 0
    return res, result


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('--openplc', required=True)
    ap.add_argument('--pilot', default='..', help='pilot folder (contains upload/)')
    ap.add_argument('--json')
    a = ap.parse_args()
    up = os.path.join(a.pilot, 'upload')
    cache = tempfile.mkdtemp(prefix='vc_')
    out = {'references': {}, 'robustness': {}, 'properties': {}, 'configuration_fault': {}, 'seeded_faults': []}
    ok_all = True
    try:
        files = {t: '%s_ref_openplc.st' % t for t in ('T1', 'T2', 'T3', 'T4')}
        src = {k: open(os.path.join(up, f), encoding='utf-8').read() for k, f in files.items()}
        print('L1 syntax: upload files and their scene-test variants compiled with iec2c and g++ (exec/scene_sim.py glue)')
        n_built = 0
        for t, f in files.items():
            for c in sim.SITUATIONS[t]:
                PLC(src[t] if t == 'T1' else scenario(src[t], t, c), a.openplc, cache)
                n_built += 1
            print('   %-22s sha256 %s' % (f, hashlib.sha256(src[t].encode()).hexdigest()[:16]))
        print('   %d programs built' % n_built)

        print('\nL3 function: registered situations, nominal scene model (%s)' % sim.SCENE_MODEL)
        for t in ('T1', 'T2', 'T3', 'T4'):
            verdict, log, result = sim.test_program(src[t], t, a.openplc, cache)
            for c, s in result['situations'].items():
                ok_all &= s['pass']
                print('   %-4s %-4s %-6s %s' % ('ok' if s['pass'] else 'FAIL', t, '(%s)' % c if t != 'T1' else 'scene', s['detail']))
                out['references']['%s %s' % (t, c)] = s
        ok = t1_extra(PLC(src['T1'], a.openplc, cache))
        print('   %-4s T1   extra  (not registered) %s' % ('ok' if ok[0] else 'FAIL', ok[1]))
        ok_all &= ok[0]

        print('\nL3 function: own configuration with another task interval (every registered situation must pass)')
        out['task_interval'] = {}
        for t in ('T1', 'T2', 'T3', 'T4'):
            for iv, ts in (('T#10ms', '0.01'), ('T#100ms', '0.1')):
                text = src[t].replace('INTERVAL := T#20ms', 'INTERVAL := %s' % iv)
                if t == 'T4':                                # the reference states its sampling period explicitly
                    text = text.replace('Ts : REAL := 0.02;', 'Ts : REAL := %s;' % ts)
                verdict, log, result = sim.test_program(text, t, a.openplc, cache)
                ok_all &= verdict == 1
                n_ok = sum(s['pass'] for s in result['situations'].values())
                print('   %-4s %-4s %-8s %d/%d situations pass (%s)' % ('ok' if verdict == 1 else 'FAIL', t, iv, n_ok,
                                                                      len(result['situations']), log[-2]))
                out['task_interval']['%s %s' % (t, iv)] = {'verdict': verdict, 'situations_pass': n_ok}

        print('\nL3 function: robustness grid (every combination must pass)')
        grids = {
            'T1': [{'dist': d, 'box': bx, 'slide': sl, 'phase': ph} for d in (0.6, 1.0, 2.0, 4.0) for bx in (0.3, 0.5)
                   for sl in (0.0, 0.1) for ph in (0, 2, 4)],
            'T2': [{'delta': d, 'lag': lg, 'phase': ph} for d in (-0.05, 0.0, 0.05) for lg in (0.0, 1.0) for ph in (0, 2, 4)],
            'T3': [{'delta': d, 'lag': lg, 'phase': ph} for d in (-0.05, 0.0, 0.05) for lg in (0.0, 1.0) for ph in (0, 2, 4)],
            'T4': [{'model': m, 'lag': lg, 'fi': fi, 'fo': fo, 'rounding': rd, 'phase': ph} for m in 'AB' for lg in (0.0, 2.0, 5.0)
                   for fi in (0.7, 1.0, 1.3) for fo in (0.7, 1.0, 1.3) for rd in ('round', 'trunc') for ph in (0, 3)
                   if not 0.3543 * fo * 0.4 * (0.8 ** 0.5 if m == 'B' else 1.0) > 0.25 * fi * 0.98],
        }
        for t in ('T1', 'T2', 'T3', 'T4'):
            n = f = 0
            worst = latest = 0.0
            for v in grids[t]:
                for c in sim.SITUATIONS[t]:
                    plc = PLC(src[t] if t == 'T1' else scenario(src[t], t, c), a.openplc, cache)
                    r = sim.run_situation(plc, t, c, v)
                    n += 1
                    f += not r[0]
                    if t == 'T4' and c == 'a':
                        worst = max(worst, r[2].get('x_max', 1.0))
                        latest = max(latest, r[2].get('end_s', 0.0))
            ok_all &= f == 0
            extra = ' (highest level %.3f, latest end %.1f s)' % (worst, latest) if t == 'T4' else ''
            print('   %-4s %-4s %4d situation runs over %d combinations, %d failed%s' % ('ok' if f == 0 else 'FAIL', t, n, len(grids[t]), f, extra))
            out['robustness'][t] = {'combinations': len(grids[t]), 'runs': n, 'failed': f}

        print('\nL2 logic: properties P1-P4 on the compiled code (300 random sequences x 400 scans each)')
        for t in ('T2', 'T3', 'T4'):
            checks, fails = properties(PLC(scenario(src[t], t, 'a'), a.openplc, cache), t)
            good = all(v == 0 for v in fails.values())
            ok_all &= good
            print('   %-4s %-4s %s' % ('ok' if good else 'FAIL', t, ', '.join('%s %d/%d' % (k, checks[k] - fails[k], checks[k]) for k in ('P1', 'P2', 'P3', 'P4'))))
            out['properties'][t] = {'checks': checks, 'fails': fails}

        print('\nConfiguration faults (each must make a registered situation fail)')
        for label, t, c, v in (('stop button normally closed', 'T2', 'a', {'nc_stop': True}),
                               ('stop button normally closed', 'T3', 'a', {'nc_stop': True}),
                               ('stop button normally closed', 'T4', 'a', {'nc_stop': True}),
                               ('driver Scale 1 instead of 100', 'T4', 'a', {'scale': 1})):
            r = sim.run_situation(PLC(scenario(src[t], t, c), a.openplc, cache), t, c, v)
            print('   %-6s %-4s %-30s %s' % ('fails' if not r[0] else 'PASSES', t, label, r[1]))
            out['configuration_fault']['%s %s' % (t, label)] = {'pass': r[0], 'detail': r[1]}
            ok_all &= not r[0]

        print('\nSeeded faults: the references pass every check; each fault must fail a registered situation or a property')
        for t in ('T1', 'T2', 'T3', 'T4'):
            res, _ = nominal_suite(src[t], t, cache, a.openplc)
            print('   reference %-3s %s' % (t, ', '.join('%s %s' % (k, 'pass' if v else 'FAIL') for k, v in res.items())))
            ok_all &= all(res.values())
        caught_all = True
        for t, name, text, kind in mutants(src):
            res, _ = nominal_suite(text, t, cache, a.openplc)
            failed = [k for k, v in res.items() if not v]
            registered = [k for k in failed if k != 'extra']
            if kind == 'allowed':
                print('   %-7s %-3s %-26s failed: %s  (variant permitted by the task card; registered checks %s)'
                      % ('allowed', t, name, ', '.join(failed) or '-', 'pass' if not registered else 'FAIL'))
                caught_all &= not registered
            else:
                caught = bool(registered)
                print('   %-7s %-3s %-26s failed: %s' % ('caught' if caught else 'MISSED', t, name, ', '.join(failed) or '-'))
                caught_all &= caught
            out['seeded_faults'].append({'task': t, 'variant': name, 'kind': kind, 'failed_checks': failed})
        ok_all &= caught_all
        print('\nresult:', 'all checks passed; every seeded fault caught' if ok_all else 'FAILED')
    finally:
        shutil.rmtree(cache, ignore_errors=True)
    if a.json:
        json.dump(out, open(a.json, 'w'), indent=1, ensure_ascii=False)
    sys.exit(0 if ok_all else 1)


if __name__ == '__main__':
    main()
