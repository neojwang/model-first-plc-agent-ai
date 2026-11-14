#!/usr/bin/env python3
"""Run NuSMV on the tank-task models and enter its verdicts in runs.csv.

  python3 nusmv/run_nusmv.py --nusmv PATH --reference                         # reference model and seeded faults
  python3 nusmv/run_nusmv.py --nusmv PATH runs.csv --base ARTIFACT_DIR          # report only
  python3 nusmv/run_nusmv.py --nusmv PATH runs.csv --base ARTIFACT_DIR --write  # also update runs.csv (.bak kept)
  python3 nusmv/run_nusmv.py --selftest [--nusmv PATH]

Run exec/score_models.py --write first.  For every parsable A1 GRAFCET of the tank tasks T2-T4 it writes a .smv file
next to the JSON and enters the explicit-state pre-check (nusmv_tool = precheck).  This script runs NuSMV on each such
file and replaces nusmv_all_hold, nusmv_failed_specs and nusmv_tool with the NuSMV result.  NuSMV does not print the
verdicts in file order, so each verdict is mapped to its property by the formula text; the property names come from the
comment line that grafcet2smv.to_smv writes above each SPEC.  As in score_models.py, the verdict is P1-P4 and W5 (every
evolution reaches a stable situation) is a diagnostic.  Each run is listed in nusmv_runs.csv next to runs.csv, with the
SHA-256 of the .smv file and of the NuSMV binary, the pre-check verdict and the NuSMV verdict; a disagreement is printed
and the NuSMV verdict is entered.  Rows without a model (nusmv_all_hold = NA: the A1 GRAFCET could not be parsed) are
left unchanged.  --reference checks nusmv/tank_reference.json and its seeded faults and writes nusmv/formal_log.txt.
Python 3.8 or later, standard library only.
"""
import argparse
import csv
import datetime
import hashlib
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, '..', 'exec'))
import grafcet2smv as G  # noqa: E402
from taskio import TANK_TASKS  # noqa: E402

VERDICT = ('P1', 'P2', 'P3', 'P4')
TIMEOUT_S = 600
SPEC_RE = re.compile(r'^-- (\S+):.*\nSPEC (.*)$', re.M)
OUT_RE = re.compile(r'^-- specification (.*?)\s+is (true|false)\s*$', re.M)
BANNER_RE = re.compile(r'This is (NuSMV \d+(?:\.\d+)*)')
LOG_FIELDS = ['run_id', 'task_id', 'smv', 'smv_sha256', 'tool', 'binary_sha256', 'precheck_all_hold',
              'precheck_failed_specs', 'nusmv_all_hold', 'nusmv_failed_specs', 'agree', 'status']


class NuSMVError(Exception):
    pass


def read_text(path):
    with open(path, encoding='utf-8') as f:
        return f.read()


def write_text(path, text):
    with open(path, 'w', encoding='utf-8') as f:
        f.write(text)


def read_csv(path):
    with open(path, encoding='utf-8', newline='') as f:
        reader = csv.DictReader(f)
        return list(reader), list(reader.fieldnames or [])


def write_csv(path, fields, rows):
    with open(path, 'w', encoding='utf-8', newline='') as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        w.writerows(rows)


def norm(f):
    return re.sub(r'[\s()]', '', f)


def sha256(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for b in iter(lambda: f.read(1 << 20), b''):
            h.update(b)
    return h.hexdigest()


def tool_info(nusmv):
    """(version, banner line, SHA-256 of the binary)."""
    try:
        p = subprocess.run([nusmv, '-h'], stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                           universal_newlines=True, timeout=60)
    except (OSError, subprocess.TimeoutExpired) as e:
        raise NuSMVError('cannot run %s: %s' % (nusmv, e))
    m = BANNER_RE.search(p.stdout)
    if not m:
        raise NuSMVError('%s did not print a NuSMV banner' % nusmv)
    line = next(x for x in p.stdout.splitlines() if 'This is' in x)
    return m.group(1), line.strip('* \t'), sha256(nusmv)


def run_model(nusmv, smv):
    """Run NuSMV on one .smv file; return {property id: verdict}."""
    text = read_text(smv)
    specs = SPEC_RE.findall(text)
    if not specs or len(specs) != len(re.findall(r'^SPEC ', text, re.M)):
        raise NuSMVError('%s: every SPEC needs the "-- ID: ..." line that grafcet2smv writes above it' % smv)
    by_text = {}
    for i, f in specs:
        k = norm(f)
        if k in by_text:
            raise NuSMVError('%s: %s and %s have the same formula text' % (smv, by_text[k], i))
        by_text[k] = i
    try:
        p = subprocess.run([nusmv, smv], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                           universal_newlines=True, timeout=TIMEOUT_S)
    except subprocess.TimeoutExpired:
        raise NuSMVError('%s: no result within %d s' % (smv, TIMEOUT_S))
    got = {}
    for f, v in OUT_RE.findall(p.stdout):
        i = by_text.get(norm(f))
        if i is None:
            raise NuSMVError('%s: verdict for a formula that is not in the file: %s' % (smv, f))
        if i in got:
            raise NuSMVError('%s: two verdicts for %s' % (smv, i))
        got[i] = (v == 'true')
    missing = [i for i, _ in specs if i not in got]
    if missing:
        tail = (p.stderr or p.stdout).strip().splitlines()[-3:]
        raise NuSMVError('%s: no verdict for %s (exit code %d) %s' % (smv, ', '.join(missing), p.returncode,
                                                                       ' | '.join(tail)))
    return got


def verdict(got):
    failed = [k for k in VERDICT if not got[k]]
    diag = [] if got.get('W5', True) else ['W5(diagnostic)']
    return ('0' if failed else '1'), ' '.join(failed + diag)


def score_runs(a):
    tool, banner, bsha = tool_info(a.nusmv)
    rows, fields = read_csv(a.runs)
    log, n_run, n_dis, n_err = [], 0, 0, 0
    for r in rows:
        if r.get('condition') != 'workflow' or r.get('task_id') not in TANK_TASKS:
            continue
        if r.get('nusmv_tool', '').startswith('NuSMV') and not a.force:
            continue
        if r.get('nusmv_all_hold') not in ('0', '1'):
            continue                                              # no model (unparsable) or not pre-checked yet
        smv = os.path.join(a.base, os.path.splitext(r['a1_grafcet_json'])[0] + '.smv')
        e = {'run_id': r['run_id'], 'task_id': r['task_id'], 'smv': os.path.relpath(smv, a.base), 'tool': tool,
             'binary_sha256': bsha, 'precheck_all_hold': r['nusmv_all_hold'],
             'precheck_failed_specs': r['nusmv_failed_specs']}
        try:
            e['smv_sha256'] = sha256(smv)
            got = run_model(a.nusmv, smv)
        except (NuSMVError, OSError) as x:
            n_err += 1
            e['status'] = 'error: %s' % x
            print('  %-24s ERROR %s' % (r['run_id'], x))
            log.append(e)
            continue
        hold, failed = verdict(got)
        e.update(nusmv_all_hold=hold, nusmv_failed_specs=failed, status='ok',
                 agree='1' if (hold, failed) == (r['nusmv_all_hold'], r['nusmv_failed_specs']) else '0')
        if e['agree'] == '0':
            n_dis += 1
            print('  %-24s pre-check %s [%s] vs NuSMV %s [%s]' % (r['run_id'], r['nusmv_all_hold'],
                                                               r['nusmv_failed_specs'], hold, failed))
        if a.write:
            r['nusmv_all_hold'], r['nusmv_failed_specs'], r['nusmv_tool'] = hold, failed, tool
        n_run += 1
        log.append(e)
    print('%s (%s; binary SHA-256 %s)' % (tool, banner, bsha))
    print('NuSMV runs: %d; disagreements with the pre-check: %d; errors: %d' % (n_run, n_dis, n_err))
    if a.write:
        logpath = os.path.join(os.path.dirname(os.path.abspath(a.runs)), 'nusmv_runs.csv')
        old = read_csv(logpath)[0] if os.path.exists(logpath) else []
        write_csv(logpath, LOG_FIELDS, old + log)
        shutil.copyfile(a.runs, a.runs + '.bak')
        write_csv(a.runs, fields, rows)
        print('updated %s (previous version kept as %s.bak); runs listed in %s' % (a.runs, a.runs, logpath))
    return 1 if n_err else 0


def reference(nusmv, out_path):
    tool, banner, bsha = tool_info(nusmv)
    spec = json.loads(read_text(os.path.join(HERE, 'tank_reference.json')))
    ids = [s['id'] for s in spec['specs']]
    work = tempfile.mkdtemp(prefix='nusmv_ref_')
    quiet = open(os.devnull, 'w')

    def run(sp, name):
        path = os.path.join(work, name + '.smv')
        write_text(path, G.to_smv(sp))
        return run_model(nusmv, path), sha256(path)

    when = datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
    L = ['Formal NuSMV run of the tank reference model and its seeded faults (nusmv/run_nusmv.py --reference)',
         'run (UTC): %s' % when, 'tool: %s' % banner, 'binary SHA-256: %s' % bsha]
    base, ref_sha = run(spec, 'tank_reference')
    kit_smv = os.path.join(HERE, 'tank_reference.smv')
    same = os.path.exists(kit_smv) and sha256(kit_smv) == ref_sha
    L.append('model: tank_reference.json -> .smv (SHA-256 %s; %s nusmv/tank_reference.smv)'
             % (ref_sha, 'identical to' if same else 'DIFFERS FROM'))
    pre = G.check(spec, out=quiet)
    ok = same
    for i in ids:
        agree = bool(pre[i]) == base[i]
        ok &= agree
        L.append('  %-3s %-5s %s%s' % (i, 'holds' if base[i] else 'FAILS', spec_ctl(spec, i),
                                       '' if agree else '   (pre-check differs)'))
    ok &= all(base.values())
    L.append('reference model: %s' % ('all specs hold' if all(base.values()) else 'SOME SPEC FAILS'))
    L.append('seeded faults (a fault is detected when a spec that holds on the reference fails):')
    n_same, killed_any = 0, set()
    for mid, desc, patch in G.MUTANTS:
        m = G.mutate(spec, patch)
        got, _ = run(m, mid)
        p = G.check(m, out=quiet)
        killed = [k for k in ids if base[k] and not got[k]]
        pkilled = [k for k in ids if pre[k] and not p[k]]
        ok &= bool(killed)
        killed_any.update(killed)
        n_same += (killed == pkilled)
        L.append('  %s %-52s detected by: %s%s' % (mid, desc, ', '.join(killed) if killed else 'NOT DETECTED',
                                                   '' if killed == pkilled else '   (pre-check: %s)'
                                                   % ', '.join(pkilled)))
    ok &= n_same == len(G.MUTANTS)
    L.append('properties that fail on at least one seeded fault: %s' % ', '.join(k for k in ids if k in killed_any))
    L.append('agreement with the explicit-state pre-check: %d of %d specs, %d of %d seeded faults'
             % (sum(bool(pre[i]) == base[i] for i in ids), len(ids), n_same, len(G.MUTANTS)))
    L.append('RESULT %s' % ('all specs hold, all seeded faults detected, same as the pre-check' if ok else 'CHECK FAILED'))
    text = '\n'.join(L) + '\n'
    print(text, end='')
    quiet.close()
    if out_path:
        write_text(out_path, text)
        print('written to', out_path)
    shutil.rmtree(work, ignore_errors=True)
    return 0 if ok else 1


def spec_ctl(spec, i):
    return next(s['ctl'] for s in spec['specs'] if s['id'] == i)


# ----------------------------------------------------------------------------------------------- self-test
STUB = r'''#!/usr/bin/env python3
import os, re, sys
print('*** This is NuSMV 2.6.0 (compiled on self-test stub)')
if sys.argv[1:] == ['-h']:
    sys.exit(1)
pairs = re.findall(r'^-- (\S+):.*\nSPEC (.*)$', open(sys.argv[1], encoding='utf-8').read(), re.M)
false, drop = set(os.environ.get('STUB_FALSE', '').split()), set(os.environ.get('STUB_DROP', '').split())
for i, f in reversed(pairs):
    if i not in drop:
        print('-- specification (%s)  is %s' % (f, 'false' if i in false else 'true'))
'''

T2 = {'graphs': [{'name': 'G1', 'steps': ['x0', 'x1', 'x2'], 'initial': ['x0']},
                 {'name': 'G0', 'steps': ['x10', 'x11'], 'initial': ['x10']}],
      'transitions': [{'id': 'a', 'from': ['x0'], 'to': ['x1'], 'guard': 'start'},
                      {'id': 'b', 'from': ['x1'], 'to': ['x2'], 'guard': 'timer_done | LSHH'},
                      {'id': 'c', 'from': ['x2'], 'to': ['x0'], 'guard': 'TRUE'},
                      {'id': 'd', 'from': ['x10'], 'to': ['x11'], 'guard': 'stop'},
                      {'id': 'e', 'from': ['x11'], 'to': ['x10'], 'guard': '!stop'}],
      'outputs': {'fill_valve': 'x1', 'discharge_valve': 'FALSE'},
      'forcing': [{'by': 'x11', 'graph': 'G1', 'situation': ['x0']}],
      'owned': {'timer_done': {'step': 'x1', 'neutral': False, 'preset': 'TimerDuration'}}}


def fixtures():
    bad = json.loads(json.dumps(T2))
    bad['transitions'][1]['guard'] = 'timer_done'                 # overfill term deleted: P1 must fail
    nostop = json.loads(json.dumps(T2))
    del nostop['forcing']                                         # stop has no effect: P2 must fail
    t4 = json.loads(json.dumps(T2).replace('timer_done | LSHH', 'settled | r = HIGH').replace('timer_done', 'settled'))
    t4['outputs']['discharge_valve'] = 'x1'
    return [('S1', 'T2', T2, ('1', '')), ('S2', 'T2', bad, ('0', 'P1')), ('S3', 'T2', nostop, None),
            ('S4', 'T4', t4, ('1', '')), ('S5', 'T3', None, None), ('S6', 'T1', T2, None)]


def selftest(nusmv=None):
    ok = True

    def check(cond, what):
        nonlocal ok
        ok &= bool(cond)
        print('  %-66s %s' % (what, 'ok' if cond else 'WRONG'))

    tmp = tempfile.mkdtemp(prefix='run_nusmv_selftest_')
    stub = os.path.join(tmp, 'nusmv_stub')
    write_text(stub, STUB)
    os.chmod(stub, os.stat(stub).st_mode | stat.S_IEXEC)
    fields = read_text(os.path.join(HERE, '..', 'analysis', 'runs_template.csv')).splitlines()[0].split(',')

    def make_runs(folder):
        os.makedirs(os.path.join(folder, 's'), exist_ok=True)
        rows = []
        for rid, task, d, _ in fixtures():
            r = dict.fromkeys(fields, '')
            r.update(run_id=rid, task_id=task, condition='workflow', a1_grafcet_json='s/%s_a1.json' % rid,
                     a2_grafcet_json='s/%s_a2.json' % rid)
            if d is not None:
                for lane in ('a1', 'a2'):
                    write_text(os.path.join(folder, 's', '%s_%s.json' % (rid, lane)), json.dumps(d))
            rows.append(r)
        runs = os.path.join(folder, 'runs.csv')
        write_csv(runs, fields, rows)
        p = subprocess.run([sys.executable, '-I', os.path.join(HERE, '..', 'exec', 'score_models.py'), runs,
                            '--base', folder, '--write'], stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                           universal_newlines=True)
        check(p.returncode == 0, 'score_models.py --write on the fixtures (pre-check, .smv files)')
        return runs

    def table(path):
        return {r['run_id']: r for r in read_csv(path)[0]}

    def call(runs, folder, binary, write, env=None):
        args = argparse.Namespace(runs=runs, base=folder, nusmv=binary, write=write, force=False)
        old = dict(os.environ)
        os.environ.update(env or {})
        try:
            with open(os.devnull, 'w') as sink:
                so, sys.stdout = sys.stdout, sink
                try:
                    return score_runs(args)
                finally:
                    sys.stdout = so
        finally:
            os.environ.clear()
            os.environ.update(old)

    print('stub NuSMV (verdicts printed in reverse order, formulas in extra parentheses):')
    folder = os.path.join(tmp, 'stub')
    runs = make_runs(folder)
    pre = table(runs)
    check(pre['S2']['nusmv_all_hold'] == '0' and 'P1' in pre['S2']['nusmv_failed_specs'],
          'fixture S2 (overfill term deleted): pre-check P1 fails')
    check(pre['S3']['nusmv_all_hold'] == '0' and 'P2' in pre['S3']['nusmv_failed_specs'],
          'fixture S3 (no stop forcing): pre-check P2 fails')
    check(pre['S5']['nusmv_all_hold'] == 'NA', 'fixture S5 (no A1 GRAFCET): NA, no model')
    smv = os.path.join(folder, 's', 'S1_a1.smv')
    ids = [i for i, _ in SPEC_RE.findall(read_text(smv))]
    check(ids == ['P1', 'P2', 'P3', 'P4', 'W5'], 'SPEC comment lines give P1-P4, W5 in file order')
    got = run_model(stub, smv)
    check(got == dict.fromkeys(ids, True), 'reverse-order verdicts mapped back by formula text')
    os.environ['STUB_FALSE'] = 'P3'
    got = run_model(stub, smv)
    del os.environ['STUB_FALSE']
    check(got['P3'] is False and all(got[k] for k in ids if k != 'P3'), 'a false verdict lands on P3 only')
    os.environ['STUB_DROP'] = 'P2'
    try:
        run_model(stub, smv)
        check(False, 'missing verdict is refused')
    except NuSMVError:
        check(True, 'missing verdict is refused')
    finally:
        del os.environ['STUB_DROP']
    dup = os.path.join(tmp, 'dup.smv')
    write_text(dup, '-- P1: a\nSPEC AG (a)\n-- P2: b\nSPEC AG a\n')
    try:
        run_model(stub, dup)
        check(False, 'two properties with the same formula text are refused')
    except NuSMVError:
        check(True, 'two properties with the same formula text are refused')
    before = read_text(runs)
    rc = call(runs, folder, stub, write=False, env={'STUB_FALSE': 'P1'})
    check(rc == 0 and read_text(runs) == before, 'report-only run leaves runs.csv unchanged')
    rc = call(runs, folder, stub, write=True, env={'STUB_FALSE': 'P1'})
    t = table(runs)
    log = table(os.path.join(folder, 'nusmv_runs.csv'))
    check(rc == 0 and os.path.exists(runs + '.bak'), '--write keeps runs.csv.bak and returns 0')
    check(t['S1']['nusmv_all_hold'] == '0' and t['S1']['nusmv_failed_specs'] == 'P1'
          and t['S1']['nusmv_tool'] == 'NuSMV 2.6.0', 'NuSMV verdict entered over the pre-check (S1)')
    check(log['S1']['agree'] == '0' and log['S2']['agree'] == '1', 'disagreement listed in nusmv_runs.csv (S1), agreement (S2)')
    check(t['S5']['nusmv_tool'] == 'precheck' and 'S5' not in log, 'row without a model left unchanged (S5)')
    check('S6' not in log, 'non-tank task skipped (S6)')
    rc = call(runs, folder, stub, write=True)
    check(rc == 0 and len(read_csv(os.path.join(folder, 'nusmv_runs.csv'))[0]) == 4,
          'rows already checked by NuSMV are skipped on a second run')
    folder = os.path.join(tmp, 'stub2')
    runs = make_runs(folder)
    rc = call(runs, folder, stub, write=True, env={'STUB_DROP': 'P4'})
    t = table(runs)
    check(rc == 1 and t['S1']['nusmv_tool'] == 'precheck', 'NuSMV error: exit code 1, pre-check left in place')
    if nusmv:
        print('real NuSMV (binary SHA-256 %s):' % sha256(nusmv)[:16])   # no local path in the log
        folder = os.path.join(tmp, 'real')
        runs = make_runs(folder)
        rc = call(runs, folder, nusmv, write=True)
        t = table(runs)
        log = read_csv(os.path.join(folder, 'nusmv_runs.csv'))[0]
        check(rc == 0 and len(log) == 4 and all(e['agree'] == '1' for e in log),
              'NuSMV agrees with the pre-check on the 4 fixture models')
        for rid, _, _, want in fixtures():
            if want:
                check((t[rid]['nusmv_all_hold'], t[rid]['nusmv_failed_specs']) == want
                      and t[rid]['nusmv_tool'].startswith('NuSMV'),
                      'fixture %s: NuSMV verdict %s' % (rid, '/'.join(x or '-' for x in want)))
        check(t['S3']['nusmv_all_hold'] == '0' and 'P2' in t['S3']['nusmv_failed_specs'], 'fixture S3: NuSMV P2 fails')
        check(reference(nusmv, None) == 0, 'reference model and seeded faults (--reference)')
    shutil.rmtree(tmp, ignore_errors=True)
    print('SELFTEST %s' % ('passed' if ok else 'FAILED'))
    return ok


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('runs', nargs='?')
    ap.add_argument('--base', default='.')
    ap.add_argument('--nusmv', help='path of the NuSMV 2.6 binary')
    ap.add_argument('--write', action='store_true')
    ap.add_argument('--force', action='store_true', help='also re-run rows already checked by NuSMV')
    ap.add_argument('--reference', action='store_true')
    ap.add_argument('--out', default=os.path.join(HERE, 'formal_log.txt'), help='log of --reference')
    ap.add_argument('--selftest', action='store_true')
    a = ap.parse_args()
    try:
        if a.selftest:
            sys.exit(0 if selftest(a.nusmv) else 1)
        if not a.nusmv:
            ap.error('--nusmv PATH is required')
        if a.reference:
            sys.exit(reference(a.nusmv, a.out))
        if not a.runs:
            ap.error('give runs.csv or --reference')
        sys.exit(score_runs(a))
    except NuSMVError as e:
        sys.exit('error: %s' % e)


if __name__ == '__main__':
    main()
