#!/usr/bin/env python3
"""Copy the public part of the kit (English files only, no internal notes, no student data) into a new folder.

  python3 exec/make_release.py OUT_DIR                                  # before the experiment
  python3 exec/make_release.py OUT_DIR --runs runs.csv --base ARTIFACTS  # after the experiment

With --runs, the run sheet and the text artifacts of every sample (models, prompts' responses, ST code,
NuSMV models, compilation and test logs), the raw responses of the model (<run_id>/raw/) and the call log
(llm_ledger.jsonl) are copied to OUT_DIR/results/, and results/manifest.csv lists every artifact with its
SHA-256; binary files such as screen recordings are listed but not copied.  The tables written by the scoring
tools and the report of analysis/analysis.py are copied too when they lie next to the run sheet (SCORING), and
the record of the pauses at the plan usage limit (pauses.jsonl) when it lies in ARTIFACTS.
"""
import argparse
import csv
import hashlib
import json
import os
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FILES = ['LICENSE', 'exec/render_prompt.py', 'exec/run_llm.py', 'exec/freeze_prompts.py', 'exec/make_run_plan.py', 'exec/run_plan.csv',
         'exec/scene_tests_en.md', 'exec/compile_check.py', 'exec/set_params.py', 'exec/scene_sim.py', 'exec/compare_grafcet.py', 'exec/score_models.py', 'exec/taskio.py',
         'nusmv/grafcet2smv.py', 'nusmv/run_nusmv.py', 'nusmv/formal_log.txt', 'nusmv/selftest_log.txt',
         'analysis/analysis.py', 'analysis/power_sim.py', 'analysis/power_log.txt',
         'analysis/runs_template.csv', 'analysis/selftest_log.txt', 'docs/use_case_variables.md']
# kit18: the reference programs and the check of the scene simulator against them (used in place of a
# comparison with runs in Factory I/O; author's ruling of 2026-11-13 13:01)
FILES += ['pilot/reference/%s_ref.st' % t for t in ('T1', 'T2', 'T3', 'T4')]
FILES += ['pilot/upload/%s_ref_openplc.st' % t for t in ('T1', 'T2', 'T3', 'T4')]
FILES += ['pilot/vc/vc_check.py', 'pilot/vc/vc_log.txt']
# kit19: GRAFCET as the description language of a GRAFCET virtual machine; equivalent Python, C++, and ST
# programs generated from the reference GRAFCET and checked in lockstep (author's request, 2026-11-13 14:12-14:17)
FILES += ['gvm/README.md', 'gvm/grafcet2gvm.py', 'gvm/e3_check.py', 'gvm/e3_log.txt', 'gvm/gvm_colab.ipynb']
FILES += ['gvm/generated/tank_reference_gvm%s' % s for s in ('.py', '.hpp', '_main.cpp', '.st', '_io.json')]
# kit25: the GRAFCET models of the samples run as GVM programs in the scene tests (author, 2026-11-14 12:39)
FILES += ['gvm/gvm_scene.py', 'gvm/scene_log.txt'] + ['gvm/reference/%s_ref.json' % t for t in ('T1', 'T2', 'T3', 'T4')]
# kit26: the release script itself (listed in the pre-registration push of protocol.md, Section 9)
FILES += ['exec/make_release.py']
# kit30: the ST programs checked against the GVM programs of their GRAFCET (author, 2026-11-14 16:49)
FILES += ['gvm/st_match.py', 'gvm/st_match_log.txt']
FILES += ['.gitattributes']
OPTIONAL = ['exec/prompts_manifest.json']        # copied once the prompts are frozen
DIRS = ['exec/prompts/tasks', 'exec/prompts/templates']
ARTIFACT_COLS = ['a1_idef0', 'a1_grafcet_json', 'st_code', 'a2_idef0', 'a2_grafcet_json', 'a2_st_code',
                 'compile_log', 'test_log']
TEXT_EXT = {'.md', '.json', '.jsonl', '.st', '.smv', '.txt', '.log', '.csv'}
SCORING = ['gvm_runs.csv', 'st_gvm_runs.csv', 'nusmv_runs.csv', 'scene_sensitivity.csv', 'results_table.csv',
           'report.md']


def add_results(out, runs, base):
    """Copy the run sheet and the text artifacts of every sample; write results/manifest.csv."""
    res = os.path.join(out, 'results')
    os.makedirs(res)
    shutil.copy2(runs, os.path.join(res, 'runs.csv'))
    rows = list(csv.DictReader(open(runs, encoding='utf-8')))
    if not rows:
        sys.exit('%s has no data rows' % runs)
    man, copied, skipped, missing = [], 0, 0, 0
    for r in rows:
        paths = [(c, r.get(c, '').strip()) for c in ARTIFACT_COLS]
        if paths[1][1]:
            paths.append(('a1_grafcet_smv', os.path.splitext(paths[1][1])[0] + '.smv'))
        for col, rel in paths:
            if not rel:
                continue
            src = os.path.join(base, rel)
            if os.path.isabs(rel) or os.path.normpath(rel).startswith('..'):
                man.append((r['run_id'], col, rel, 'rejected (outside the artifact folder)', '', ''))
                missing += 1
                continue
            if not os.path.isfile(src):
                man.append((r['run_id'], col, rel, 'missing', '', ''))
                missing += 1
                continue
            data = open(src, 'rb').read()
            ext = os.path.splitext(rel)[1].lower()
            if ext in TEXT_EXT:
                dst = os.path.join(res, rel)
                os.makedirs(os.path.dirname(dst), exist_ok=True)
                shutil.copy2(src, dst)
                state = 'included'
                copied += 1
            else:
                state = 'not included (binary)'
                skipped += 1
            man.append((r['run_id'], col, rel, state, hashlib.sha256(data).hexdigest(), len(data)))
        raw = os.path.join(base, r['run_id'], 'raw')
        if os.path.isdir(raw):
            for name in sorted(os.listdir(raw)):
                src = os.path.join(raw, name)
                rel = '%s/raw/%s' % (r['run_id'], name)
                if not os.path.isfile(src) or os.path.splitext(name)[1].lower() not in TEXT_EXT:
                    continue
                data = open(src, 'rb').read()
                dst = os.path.join(res, rel)
                os.makedirs(os.path.dirname(dst), exist_ok=True)
                shutil.copy2(src, dst)
                copied += 1
                man.append((r['run_id'], 'raw', rel, 'included', hashlib.sha256(data).hexdigest(), len(data)))
    extra = [('ledger', os.path.join(base, 'llm_ledger.jsonl')), ('pauses', os.path.join(base, 'pauses.jsonl'))]
    extra += [('scoring', os.path.join(os.path.dirname(os.path.abspath(runs)), n)) for n in SCORING]
    for col, src in extra:
        if os.path.isfile(src):
            name = os.path.basename(src)
            data = open(src, 'rb').read()
            shutil.copy2(src, os.path.join(res, name))
            copied += 1
            man.append(('', col, name, 'included', hashlib.sha256(data).hexdigest(), len(data)))
    with open(os.path.join(res, 'manifest.csv'), 'w', encoding='utf-8', newline='') as f:
        w = csv.writer(f)
        w.writerow(['run_id', 'column', 'path', 'state', 'sha256', 'bytes'])
        w.writerows(man)
    print('results: %d rows; %d files copied, %d binary files listed only, %d missing' % (len(rows), copied, skipped,
                                                                                          missing))


def main():
    ap = argparse.ArgumentParser(description='Copy the public part of the kit into a new folder.')
    ap.add_argument('out')
    ap.add_argument('--runs', help='run sheet (runs.csv) filled during the experiment')
    ap.add_argument('--base', default='.', help='folder that the artifact paths of the run sheet are relative to')
    a = ap.parse_args()
    out = a.out
    if os.path.exists(out):
        sys.exit('%s exists; give a new folder' % out)
    for f in FILES:
        os.makedirs(os.path.join(out, os.path.dirname(f)), exist_ok=True)
        shutil.copy2(os.path.join(ROOT, f), os.path.join(out, f))
    for f in OPTIONAL:
        if os.path.exists(os.path.join(ROOT, f)):
            shutil.copy2(os.path.join(ROOT, f), os.path.join(out, f))
    for d in DIRS:
        shutil.copytree(os.path.join(ROOT, d), os.path.join(out, d))
    shutil.copy2(os.path.join(ROOT, 'README_public.md'), os.path.join(out, 'README.md'))
    ref = json.load(open(os.path.join(ROOT, 'nusmv', 'tank_reference.json'), encoding='utf-8'))
    ref.pop('not_used', None)
    json.dump(ref, open(os.path.join(out, 'nusmv', 'tank_reference.json'), 'w', encoding='utf-8'), indent=1)
    log = subprocess.run([sys.executable, '-I', 'grafcet2smv.py', 'tank_reference.json', '--smv', 'tank_reference.smv',
                          '--selfcheck', 'tank_reference.smv', '--check', '--mutants'],
                         cwd=os.path.join(out, 'nusmv'), capture_output=True, text=True, check=True).stdout
    open(os.path.join(out, 'nusmv', 'check_log.txt'), 'w', encoding='utf-8').write(log)
    if a.runs:
        add_results(out, a.runs, a.base)
    n = sum(len(fs) for _, _, fs in os.walk(out))
    print('release written to %s (%d files)' % (out, n))


if __name__ == '__main__':
    main()
