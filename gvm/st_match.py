#!/usr/bin/env python3
"""Synchronous check of an ST program against the GVM program of a GRAFCET: does the ST program, compiled to C by
matiec and run as in exec/scene_sim.py, do what the GRAFCET does?

Method.  In every registered situation of the scene tests, the GVM program of the GRAFCET (gvm/gvm_scene.py: Python,
with the binding of the task card) drives the scene model, and the ST program runs beside it: in every scan it gets
the same input image (same located inputs, same scan period, that of the ST configuration), and its located outputs
are compared with those of the GVM program.  Compared: T1 the conveyor (%QX100.0); T2 and T3 the fill and discharge
valves (%QX100.0, %QX100.1); T4 the discharge valve open or closed (%QW101 > 0) and, while the GRAFCET has the fill
valve off, a closed fill valve (%QW100 = 0).  The opening of the fill valve under PID control is not compared: the
controller of the ST program is its own.
A difference that lasts one scan is tolerated: in a GRAFCET a step that is left in the same evolution shows no
output, while an ST program that fires one transition per scan shows it for one scan, and a change may come one scan
earlier or later.  The verdict is 1 when no difference lasts two scans or more in any registered situation; the
number of such lasting differences is reported.  NA when the ST program does not compile, or when the GRAFCET does not
give a program (gvm/gvm_scene.py).
In T4 the band check |e| <= eps decides when the hold time runs; at the two level counts on the edge of the band
(h_sp - eps and h_sp + eps) equivalent REAL formulas round differently, so either reading is accepted (amended
2026-11-15, protocol.md): the GVM program runs every situation once for each reading of the two edge counts (in or
out of the band), and the situation matches when the ST program agrees with one of them.
For a workflow sample the ST program of a lane is checked against the GRAFCET of the same lane (A1 ST with A1
GRAFCET, A2 ST with A2 GRAFCET).

Usage:
  python3 gvm/st_match.py --openplc OPENPLC_V3_DIR --reference [--log gvm/st_match_log.txt]
  python3 gvm/st_match.py --openplc OPENPLC_V3_DIR runs.csv --base ARTIFACT_DIR [--write]
  python3 gvm/st_match.py --openplc OPENPLC_V3_DIR --selftest
Python 3.8 or later, standard library only; OpenPLC_v3 with matiec and g++, as for exec/scene_sim.py.
"""
import argparse
import copy
import csv
import datetime
import hashlib
import importlib.util
import json
import os
import platform
import re
import shutil
import sys
import tempfile

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
KIT = os.path.dirname(HERE)


def _load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


GS = _load(os.path.join(HERE, 'gvm_scene.py'), 'gvm_scene')
SIM, GEN = GS.SIM, GS.GEN
CC, SETP = SIM.compile_check, SIM.set_params
COLS = ['st_gvm_match', 'st_gvm_lasting', 'a2_st_gvm_match', 'a2_st_gvm_lasting']


def differs(task, g, s):
    if task == 'T1':
        return bool(g.get('%QX100.0')) != bool(s.get('%QX100.0'))
    if task in ('T2', 'T3'):
        return any(bool(g.get(l)) != bool(s.get(l)) for l in ('%QX100.0', '%QX100.1'))
    return (g.get('%QW101') > 0) != (s.get('%QW101') > 0) or (not g.o.get('fill_valve', False) and s.get('%QW100') > 0)


class Shadow:
    """The PLC seen by the scene tests: the GVM program drives, the ST program follows with the same inputs."""

    def __init__(self, task, g, s):
        self.task, self.g, self.s = task, g, s
        self.g.ts = s.ts
        self.ts = s.ts
        self.missing = set()
        self.diff = self.lasting = self.run = self.longest = self.n = 0

    def reset(self):
        self.g.reset()
        self.s.reset()
        self.diff = self.lasting = self.run = self.longest = self.n = 0

    def set(self, loc, v):
        self.g.set(loc, v)
        self.s.set(loc, v)

    def get(self, loc):
        return self.g.get(loc)

    def scan(self):
        self.g.scan()
        self.s.scan()
        self.n += 1
        if differs(self.task, self.g, self.s):
            self.diff += 1
            self.run += 1
            self.lasting += self.run == 2
            self.longest = max(self.longest, self.run)
        else:
            self.run = 0

    # situation of the GVM program (kept for diagnostics)
    @property
    def sit(self):
        return self.g.sit

    @property
    def init_sit(self):
        return self.g.init_sit


EDGES = ((False, True), (False, False), (True, True), (True, False))   # T4: (lower, upper) edge count in the band;
                                                                    # the first is the registered REAL rule


def edge_label(edge):
    lo, hi = GS.SP_COUNTS - GS.EPS_COUNTS, GS.SP_COUNTS + GS.EPS_COUNTS
    return '%d %s, %d %s' % (lo, 'in' if edge[0] else 'out', hi, 'in' if edge[1] else 'out')


def compare(task, st_text, d, label, openplc, work):
    """One ST program against one GRAFCET.  Returns a result dictionary."""
    out = {'match': 'NA', 'lasting': 'NA', 'reason': '', 'log': [], 'situations': {}}
    try:
        spec, notes = GS.gvm_spec(task, d, re.sub(r'[^A-Za-z0-9_]', '_', label)[:40])
    except GS.NA as e:
        out['reason'] = 'GRAFCET: %s' % e
        return out
    gdir = os.path.join(work, spec['name'])
    GEN.generate(None, gdir, spec=spec)
    tmp = os.path.join(work, spec['name'] + '_src.st')
    with open(tmp, 'w', encoding='utf-8') as f:
        f.write(st_text)
    wrapped, note, _ = CC.prepare(tmp)
    if wrapped is None:
        out['reason'] = 'ST: %s' % note
        return out
    total = 0
    verdict = 1
    missing = set()
    for case in SIM.SITUATIONS[task]:
        text = wrapped if task == 'T1' else SETP.set_params(wrapped, SETP.SCENARIOS[(task, case)])[0]
        try:
            st = SIM.PLC(text, openplc, work)
        except Exception as e:                       # the ST program does not compile or build
            out['reason'] = 'ST: %s' % str(e)[:200]
            out['match'] = out['lasting'] = 'NA'
            return out
        best = None
        for edge in (EDGES if task == 'T4' else (None,)):
            g = GS.GvmPLC(task, GS.PyCore(gdir, spec['name']), spec, GS.situation_params(task, case), edge=edge)
            sh = Shadow(task, g, st)
            SIM.run_situation(sh, task, case, {})
            if best is None or sh.lasting < best[0].lasting:
                best = (sh, edge)
            if sh.lasting == 0:
                break
        sh, edge = best
        missing |= st.missing
        total += sh.lasting
        verdict &= sh.lasting == 0
        out['situations'][case] = {'scans': sh.n, 'different': sh.diff, 'lasting': sh.lasting, 'longest': sh.longest}
        if edge is not None:
            out['situations'][case]['edge'] = edge_label(edge)
        out['log'].append('%s (%s): %d scans, %d different, %d lasting (longest %d scans)%s' % (
            task, case, sh.n, sh.diff, sh.lasting, sh.longest, '; band edge ' + edge_label(edge) if edge else ''))
    out['match'], out['lasting'] = int(verdict), total
    if missing:
        out['log'].append('I/O not declared by the ST program (not connected): %s' % ', '.join(sorted(missing)))
    return out


def load_json(path):
    with open(path, encoding='utf-8', errors='replace') as f:
        return json.load(f)


def read(path):
    with open(path, encoding='utf-8', errors='replace') as f:
        return f.read()


# ---------------------------------------------------------------- reference programs and seeded faults

def reference(openplc, log_path):
    lines = []
    say = lambda s='': (lines.append(s), print(s))
    sha = lambda p: hashlib.sha256(open(p, 'rb').read()).hexdigest()[:16]
    vc = _load(os.path.join(KIT, 'pilot', 'vc', 'vc_check.py'), 'vc_check')
    up = os.path.join(KIT, 'pilot', 'upload')
    src = {t: read(os.path.join(up, '%s_ref_openplc.st' % t)) for t in ('T1', 'T2', 'T3', 'T4')}
    ref = {t: load_json(os.path.join(HERE, 'reference', '%s_ref.json' % t)) for t in ('T1', 'T2', 'T3', 'T4')}
    say('Synchronous check of ST programs against GVM programs (gvm/st_match.py --reference)')
    say('date (UTC): %s' % datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%d %H:%M'))
    say('Python %s; %s; %s' % (platform.python_version(), GS.gpp_version() or 'g++ not found', SIM.SCENE_MODEL))
    say('SHA-256 (first 16): st_match.py %s, gvm_scene.py %s, scene_sim.py %s' % (
        sha(os.path.abspath(__file__)), sha(os.path.join(HERE, 'gvm_scene.py')), sha(os.path.join(KIT, 'exec', 'scene_sim.py'))))
    say()
    work = tempfile.mkdtemp(prefix='st_match_')
    ok_all = True
    try:
        say('1. Reference ST programs (pilot/upload/) against the reference GRAFCETs (gvm/reference/): must match.')
        for t in ('T1', 'T2', 'T3', 'T4'):
            r = compare(t, src[t], ref[t], 'R_%s' % t, openplc, work)
            ok_all &= r['match'] == 1
            say('%s: match %s, lasting differences %s%s' % (t, r['match'], r['lasting'], ' (%s)' % r['reason'] if r['reason'] else ''))
            for l in r['log']:
                say('   ' + l)
        say()
        say('2. Seeded faults of the GRAFCET (gvm/gvm_scene.py) against the reference ST programs: must not match.')
        for k, (t, label, mut) in enumerate(GS.FAULTS, 1):
            r = compare(t, src[t], mut(copy.deepcopy(ref[t])), 'G%02d_%s' % (k, t), openplc, work)
            good = r['match'] == 0
            ok_all &= good
            say('F%02d %s, %s: match %s, lasting %s -> %s' % (k, t, label, r['match'], r['lasting'],
                                                              'detected' if good else 'NOT DETECTED'))
        say()
        say('3. Seeded faults of the ST programs (pilot/vc/vc_check.py) against the reference GRAFCETs: a fault of the')
        say('   sequence must not match; a fault of the PID controller is outside the comparison; SR in place of RS is')
        say('   a variant that the task card allows.')
        for t, name, text, kind in vc.mutants(src):
            r = compare(t, text, ref[t], 'S_%s_%s' % (t, name.split()[0]), openplc, work)
            if kind == 'allowed':
                expect, what = 1, 'allowed variant'
            elif t == 'T4' and 'windup' in name:
                expect, what = 1, 'controller, not compared'
            else:
                expect, what = 0, 'fault of the sequence'
            good = r['match'] == expect
            ok_all &= good
            say('%s %s (%s): match %s, lasting %s -> %s' % (t, name, what, r['match'], r['lasting'],
                                                            'as expected' if good else 'NOT AS EXPECTED'))
        say()
        say('verdict: %s' % ('the references match, every seeded fault of the sequence is detected' if ok_all
                             else 'NOT OK (see above)'))
    finally:
        shutil.rmtree(work, ignore_errors=True)
    if log_path:
        with open(log_path, 'w', encoding='utf-8') as f:
            f.write('\n'.join(lines) + '\n')
    return 0 if ok_all else 1


# ---------------------------------------------------------------- samples

def run_csv(a):
    with open(a.runs, encoding='utf-8') as f:
        reader = csv.DictReader(f)
        rows, fields = list(reader), list(reader.fieldnames or [])
    work = tempfile.mkdtemp(prefix='st_match_')
    out_rows = []
    try:
        for r in rows:
            if r.get('condition') != 'workflow':
                continue
            for lane, stcol, gcol, pre in (('A1', 'st_code', 'a1_grafcet_json', ''), ('A2', 'a2_st_code', 'a2_grafcet_json', 'a2_')):
                try:
                    st_text, d = read(os.path.join(a.base, r[stcol])), load_json(os.path.join(a.base, r[gcol]))
                except (OSError, ValueError) as e:
                    res = {'match': 'NA', 'lasting': 'NA', 'reason': 'file missing or not JSON (%s)' % type(e).__name__, 'log': []}
                else:
                    res = compare(r['task_id'], st_text, d, '%s_%s' % (r['run_id'], lane), a.openplc, work)
                r[pre + 'st_gvm_match'], r[pre + 'st_gvm_lasting'] = str(res['match']), str(res['lasting'])
                out_rows.append({'run_id': r['run_id'], 'task_id': r['task_id'], 'lane': lane, 'st': r[stcol],
                                 'grafcet': r[gcol], 'match': res['match'], 'lasting': res['lasting'],
                                 'reason': res['reason'], 'situations': ' | '.join(res['log'])})
                print('%s %s: match %s, lasting %s%s' % (r['run_id'], lane, res['match'], res['lasting'],
                                                         ' (%s)' % res['reason'][:120] if res['reason'] else ''))
    finally:
        shutil.rmtree(work, ignore_errors=True)
    path = os.path.join(os.path.dirname(os.path.abspath(a.runs)), 'st_gvm_runs.csv')
    with open(path, 'w', encoding='utf-8', newline='') as f:
        w = csv.DictWriter(f, fieldnames=list(out_rows[0].keys()) if out_rows else ['run_id'])
        w.writeheader()
        w.writerows(out_rows)
    print('%d ST programs compared; details in %s' % (len(out_rows), path))
    if a.write:
        shutil.copyfile(a.runs, a.runs + '.bak')
        fields += [c for c in COLS if c not in fields]
        with open(a.runs, 'w', encoding='utf-8', newline='') as f:
            w = csv.DictWriter(f, fieldnames=fields)
            w.writeheader()
            w.writerows(rows)
        print('updated', a.runs, '(previous version kept as %s.bak)' % a.runs)
    return 0


def selftest(openplc):
    work = tempfile.mkdtemp(prefix='st_match_')
    ok = True

    def check(cond, what):
        nonlocal ok
        ok &= bool(cond)
        print('%s  %s' % ('ok  ' if cond else 'FAIL', what))
    try:
        up = os.path.join(KIT, 'pilot', 'upload')
        src = read(os.path.join(up, 'T2_ref_openplc.st'))
        ref = load_json(os.path.join(HERE, 'reference', 'T2_ref.json'))
        r = compare('T2', src, ref, 'st_T2', openplc, work)
        check(r['match'] == 1, 'T2 reference ST matches the T2 reference GRAFCET')
        r = compare('T2', src, GS.FAULTS[2][2](copy.deepcopy(ref)), 'st_T2f', openplc, work)
        check(r['match'] == 0 and r['lasting'] > 0, 'a seeded fault of the GRAFCET is a lasting difference')
        bad = src.replace('ELSIF xe1 AND (fill_timer.Q OR lshh) THEN', 'ELSIF xe1 AND fill_timer.Q THEN')
        r = compare('T2', bad, ref, 'st_T2s', openplc, work)
        check(r['match'] == 0, 'a seeded fault of the ST program is a lasting difference')
        r = compare('T2', 'PROGRAM Main\nVAR x : BOOL; END_VAR\nx := ;\nEND_PROGRAM\n', ref, 'st_bad', openplc, work)
        check(r['match'] == 'NA', 'NA for an ST program that does not compile (%s)' % r['reason'][:60])
        r = compare('T2', src, ['x0'], 'st_badg', openplc, work)
        check(r['match'] == 'NA', 'NA for a GRAFCET that gives no program')
    finally:
        shutil.rmtree(work, ignore_errors=True)
    print('selftest: %s' % ('passed' if ok else 'FAILED'))
    return 0 if ok else 1


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('runs', nargs='?')
    ap.add_argument('--base', default='.')
    ap.add_argument('--write', action='store_true')
    ap.add_argument('--openplc', required=True)
    ap.add_argument('--reference', action='store_true')
    ap.add_argument('--log', default=os.path.join(HERE, 'st_match_log.txt'))
    ap.add_argument('--selftest', action='store_true')
    a = ap.parse_args()
    if a.selftest:
        return selftest(a.openplc)
    if a.reference:
        return reference(a.openplc, a.log)
    if a.runs:
        return run_csv(a)
    ap.print_help()
    return 2


if __name__ == '__main__':
    sys.exit(main())
