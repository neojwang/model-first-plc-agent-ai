#!/usr/bin/env python3
"""Compile check of the generated ST programs: fills compiled and a2_compiled in runs.csv.

The check repeats, for one program, the first three steps of the compilation script of OpenPLC Runtime
version 3 (webserver/scripts/compile_program.sh, Linux branch) at the pinned commit:

  1. iec2c -f -l -p -r -R -a <file>     with the runtime's ST library, <OpenPLC_v3>/webserver/lib
  2. g++ -std=gnu++11 -I <OpenPLC_v3>/webserver/core/lib -c Config0.c -w
  3. g++ -std=gnu++11 -I <OpenPLC_v3>/webserver/core/lib -c Res0.c -w

A program counts as compiled (1) when the three steps succeed and iec2c has produced Config0.c and Res0.c,
which the runtime script needs; otherwise it counts as not compiled (0).  Linking with the runtime core is not
repeated, because it does not depend on the program.

The prompts ask for one PROGRAM and one FUNCTION_BLOCK, without a configuration.  When the file has no
CONFIGURATION, the script appends the fixed block below, which runs the PROGRAM named Main (or, if there is none,
the first PROGRAM) every 20 ms.  This is the only change made to the generated code for the compile check; the result
is written next to the original as <name>_openplc.st.  For each situation of the scene test, set_params.py then sets
the parameter values that scene_tests_en.md gives, and that file is the one to upload.  A file without any PROGRAM
counts as not compiled.

    CONFIGURATION Config0
      RESOURCE Res0 ON PLC
        TASK TaskMain(INTERVAL := T#20ms, PRIORITY := 0);
        PROGRAM Inst0 WITH TaskMain : <program name>;
      END_RESOURCE
    END_CONFIGURATION

Usage:
  python3 compile_check.py --openplc OPENPLC_V3_DIR --file prog.st              # one file
  python3 compile_check.py --openplc OPENPLC_V3_DIR runs.csv --base ARTIFACT_DIR          # report only
  python3 compile_check.py --openplc OPENPLC_V3_DIR runs.csv --base ARTIFACT_DIR --write  # also update runs.csv
  python3 compile_check.py --openplc OPENPLC_V3_DIR --selftest ../pilot         # reference must compile, negatives must not

With --write, compiled (A1 or baseline program, column st_code) and a2_compiled (column a2_st_code) are filled for
every row whose program file exists, and the full output of every step is written to the file of column
compile_log.  Rows whose program file is missing are left empty.  A copy of runs.csv is kept as runs.csv.bak.
"""
import argparse
import csv
import hashlib
import os
import re
import shutil
import subprocess
import sys
import tempfile

TASK_INTERVAL = 'T#20ms'
CONFIG = ('\n(* Configuration appended by compile_check.py: the only change to the generated code. *)\n'
          'CONFIGURATION Config0\n'
          '  RESOURCE Res0 ON PLC\n'
          '    TASK TaskMain(INTERVAL := %s, PRIORITY := 0);\n'
          '    PROGRAM Inst0 WITH TaskMain : %s;\n'
          '  END_RESOURCE\n'
          'END_CONFIGURATION\n')


def strip_comments(code):
    code = re.sub(r'\(\*.*?\*\)', ' ', code, flags=re.S)
    return re.sub(r'//[^\n]*', ' ', code)


def tools(openplc):
    lib = os.path.join(openplc, 'webserver', 'lib')
    core_lib = os.path.join(openplc, 'webserver', 'core', 'lib')
    iec2c = next((p for p in (os.path.join(openplc, 'webserver', 'iec2c'),
                              os.path.join(openplc, 'utils', 'matiec_src', 'iec2c')) if os.path.isfile(p)), None)
    missing = [p for p in (lib, core_lib) if not os.path.isdir(p)] + ([] if iec2c else ['iec2c'])
    if missing:
        sys.exit('OpenPLC_v3 folder incomplete, missing: %s (build matiec as in exec/README.md, step 1)' % missing)
    return iec2c, lib, core_lib


def versions(openplc, iec2c):
    out = []
    try:
        head = subprocess.run(['git', '-C', openplc, 'rev-parse', 'HEAD'], capture_output=True, text=True)
        out.append('OpenPLC_v3 commit: %s' % (head.stdout.strip() or 'unknown'))
    except OSError:
        out.append('OpenPLC_v3 commit: unknown')
    v = subprocess.run([iec2c, '-v'], capture_output=True, text=True)
    out.append('iec2c: %s' % ' '.join((v.stdout + v.stderr).split())[:80])
    g = subprocess.run(['g++', '--version'], capture_output=True, text=True)
    out.append('g++: %s' % (g.stdout.splitlines() or ['unknown'])[0])
    return out


def prepare(src_path):
    """Return (text to compile, note, program name or None)."""
    code = open(src_path, encoding='utf-8', errors='replace').read()
    bare = strip_comments(code)
    if re.search(r'\bCONFIGURATION\b', bare, re.I):
        return code, 'configuration present in the file; compiled as is', 'configuration'
    names = re.findall(r'\bPROGRAM\s+([A-Za-z_]\w*)', bare, re.I)
    if not names:
        return None, 'no PROGRAM in the file: nothing the runtime could run', None
    name = next((n for n in names if n.lower() == 'main'), names[0])
    return code.rstrip() + '\n' + CONFIG % (TASK_INTERVAL, name), 'configuration appended for PROGRAM %s' % name, name


def compile_one(src_path, openplc, keep_wrapped=True, shown_path=None):
    """Compile one program; return (verdict 0/1, log text).  Paths in the log are relative, so logs can be released."""
    iec2c, lib, core_lib = tools(openplc)
    raw = open(src_path, 'rb').read()
    log = ['file: %s' % (shown_path or os.path.basename(src_path)), 'sha256: %s' % hashlib.sha256(raw).hexdigest()]
    text, note, name = prepare(src_path)
    log.append('preparation: %s' % note)
    if text is None:
        log.append('verdict: 0')
        return 0, '\n'.join(log)
    work = tempfile.mkdtemp(prefix='cc_')
    try:
        st = os.path.join(work, 'program.st')
        open(st, 'w', encoding='utf-8').write(text)
        if keep_wrapped and name != 'configuration':
            base, _ = os.path.splitext(src_path)
            open(base + '_openplc.st', 'w', encoding='utf-8').write(text)
            log.append('uploaded file for the scene test: %s_openplc.st' % os.path.basename(base))
        steps = [[iec2c, '-f', '-l', '-p', '-r', '-R', '-a', '-I', lib, '-T', work, st],
                 ['g++', '-std=gnu++11', '-I', core_lib, '-c', 'Config0.c', '-w'],
                 ['g++', '-std=gnu++11', '-I', core_lib, '-c', 'Res0.c', '-w']]
        for i, cmd in enumerate(steps, 1):
            if i == 2 and not all(os.path.isfile(os.path.join(work, f)) for f in ('Config0.c', 'Res0.c')):
                log.append('step 2: Config0.c or Res0.c not produced by iec2c (the runtime script stops here)')
                log.append('verdict: 0')
                return 0, '\n'.join(log)
            p = subprocess.run(cmd, cwd=work, capture_output=True, text=True)
            alias = {iec2c: 'iec2c', lib: '<OpenPLC_v3>/webserver/lib', core_lib: '<OpenPLC_v3>/webserver/core/lib',
                     work: '<tmp>', st: '<tmp>/program.st'}
            shown = ' '.join(alias.get(c, c) for c in cmd)
            output = (p.stdout + p.stderr).replace(work, '<tmp>').strip()
            log.append('step %d: %s\nexit %d\n%s' % (i, shown, p.returncode, output))
            if p.returncode != 0:
                log.append('verdict: 0')
                return 0, '\n'.join(log)
        log.append('verdict: 1')
        return 1, '\n'.join(log)
    finally:
        shutil.rmtree(work, ignore_errors=True)


def run_csv(a):
    rows = list(csv.DictReader(open(a.runs, encoding='utf-8')))
    if not rows:
        sys.exit('%s has no rows' % a.runs)
    fields = list(rows[0].keys())
    iec2c, _, _ = tools(a.openplc)
    header = versions(a.openplc, iec2c)
    counts = {}
    for r in rows:
        jobs = [('compiled', 'st_code', 'A1' if r['condition'] == 'workflow' else 'baseline')]
        if r['condition'] == 'workflow':
            jobs.append(('a2_compiled', 'a2_st_code', 'A2'))
        parts = []
        for col, path_col, label in jobs:
            rel = r.get(path_col, '').strip()
            path = os.path.join(a.base, rel)
            if not rel or not os.path.isfile(path):
                continue
            verdict, text = compile_one(path, a.openplc, shown_path=rel)
            r[col] = str(verdict)
            parts.append('== %s (%s) ==\n%s' % (label, path_col, text))
            counts.setdefault((r['task_id'], r['condition'], label), [0, 0])[verdict] += 1
        if parts and a.write and r.get('compile_log', '').strip():
            log_path = os.path.join(a.base, r['compile_log'].strip())
            os.makedirs(os.path.dirname(log_path) or '.', exist_ok=True)
            open(log_path, 'w', encoding='utf-8').write('\n'.join(header) + '\n\n' + '\n\n'.join(parts) + '\n')
    print('task condition program  compiled  not_compiled')
    for k in sorted(counts):
        print('%-4s %-9s %-8s %8d  %12d' % (k[0], k[1], k[2], counts[k][1], counts[k][0]))
    if not counts:
        print('no program files found under', a.base)
    if a.write:
        shutil.copyfile(a.runs, a.runs + '.bak')
        w = csv.DictWriter(open(a.runs, 'w', encoding='utf-8', newline=''), fieldnames=fields)
        w.writeheader()
        w.writerows(rows)
        print('updated', a.runs, '(previous version kept as %s.bak)' % a.runs)


def selftest(a):
    """Every file in <pilot>/reference must compile, every file in <pilot>/negative must not."""
    ok = True
    iec2c, _, _ = tools(a.openplc)
    print('\n'.join(versions(a.openplc, iec2c)))
    for sub, expect in (('reference', 1), ('negative', 0)):
        folder = os.path.join(a.selftest, sub)
        for f in sorted(os.listdir(folder)):
            if not f.endswith('.st') or f.endswith('_openplc.st'):
                continue
            verdict, text = compile_one(os.path.join(folder, f), a.openplc, keep_wrapped=False)
            good = verdict == expect
            ok &= good
            reason = '' if verdict else [l for l in text.splitlines() if 'error' in l.lower() or 'no PROGRAM' in l][:1]
            print('%-4s %-9s %-40s compiled=%d %s' % ('ok' if good else 'FAIL', sub, f, verdict,
                                                       (reason[0][:90] if reason else '')))
    print('selftest:', 'passed' if ok else 'FAILED')
    sys.exit(0 if ok else 1)


def main():
    ap = argparse.ArgumentParser(description='Compile check of generated ST programs (OpenPLC Runtime v3 steps).')
    ap.add_argument('runs', nargs='?')
    ap.add_argument('--openplc', required=True, help='OpenPLC_v3 folder at the pinned commit, with matiec built')
    ap.add_argument('--base', default='.')
    ap.add_argument('--write', action='store_true')
    ap.add_argument('--file')
    ap.add_argument('--selftest', metavar='PILOT_DIR')
    a = ap.parse_args()
    if a.selftest:
        selftest(a)
    elif a.file:
        verdict, text = compile_one(a.file, a.openplc)
        iec2c, _, _ = tools(a.openplc)
        print('\n'.join(versions(a.openplc, iec2c)) + '\n' + text)
        sys.exit(0 if verdict else 1)
    elif a.runs:
        run_csv(a)
    else:
        ap.error('give runs.csv, --file or --selftest')


if __name__ == '__main__':
    main()
