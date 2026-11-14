#!/usr/bin/env python3
"""Pre-registered analysis for the IJEE Agent AI PLC study (RQ1 and RQ2).

Usage:
  python3 analysis.py runs.csv [--table9 table9.csv] > report.md
  python3 analysis.py --selftest          # checks the statistics against scipy on synthetic inputs

runs.csv   one row per generated program (columns: see runs_template.csv and exec/run_plan.csv)

Uses scipy for Fisher's exact test when it is installed; otherwise falls back to the pure-Python version below.
"""
import csv
import math
import sys
from collections import defaultdict

try:
    from scipy import stats as SS
except Exception:  # pragma: no cover
    SS = None


# ------------------------------------------------------------------ proportions
def wilson(k, n, z=1.959963984540054):
    if n == 0:
        return (float('nan'), float('nan'))
    p, d = k / n, 1 + z * z / n
    c = (p + z * z / (2 * n)) / d
    h = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / d
    return (max(0.0, c - h), min(1.0, c + h))


def pass_at_k(n, c, k):
    """Unbiased estimator of pass@k (Chen et al.): 1 - C(n-c, k)/C(n, k)."""
    if n - c < k:
        return 1.0
    return 1.0 - math.comb(n - c, k) / math.comb(n, k)


def fisher_exact(a, b, c, d):
    """Two-sided Fisher exact test for [[a, b], [c, d]]."""
    if SS is not None:
        return SS.fisher_exact([[a, b], [c, d]], alternative='two-sided').pvalue
    r1, c1, n = a + b, a + c, a + b + c + d
    lo, hi = max(0, c1 - (n - r1)), min(r1, c1)

    def pmf(x):
        return math.comb(c1, x) * math.comb(n - c1, r1 - x) / math.comb(n, r1)
    p0 = pmf(a)
    return min(1.0, sum(pmf(x) for x in range(lo, hi + 1) if pmf(x) <= p0 * (1 + 1e-7)))


def cmh(tables):
    """Cochran-Mantel-Haenszel test (continuity-corrected) and MH common odds ratio.
    tables: list of (a, b, c, d) with rows = condition (workflow, baseline), cols = (pass, fail)."""
    num = var = 0.0
    r_num = r_den = 0.0
    for a, b, c, d in tables:
        n = a + b + c + d
        if n < 2:
            continue
        e = (a + b) * (a + c) / n
        v = (a + b) * (c + d) * (a + c) * (b + d) / (n * n * (n - 1))
        num += a - e
        var += v
        r_num += a * d / n
        r_den += b * c / n
    if var == 0:
        return float('nan'), float('nan'), float('nan')
    chi2 = (abs(num) - 0.5) ** 2 / var
    p = math.erfc(math.sqrt(chi2 / 2))
    orr = r_num / r_den if r_den > 0 else float('inf')
    return chi2, p, orr


def cohen_kappa(n11, n10, n01, n00):
    n = n11 + n10 + n01 + n00
    if n == 0:
        return float('nan'), (float('nan'), float('nan')), float('nan')
    po = (n11 + n00) / n
    pe = ((n11 + n10) * (n11 + n01) + (n01 + n00) * (n10 + n00)) / (n * n)
    if pe == 1:
        return float('nan'), (float('nan'), float('nan')), po
    k = (po - pe) / (1 - pe)
    se = math.sqrt(po * (1 - po) / (n * (1 - pe) ** 2))
    return k, (k - 1.96 * se, k + 1.96 * se), po


# ------------------------------------------------------------------ report
def b(v):
    return str(v).strip() in ('1', 'true', 'True', 'TRUE', 'yes')


def report_runs(rows, out):
    by = defaultdict(list)
    for r in rows:
        by[(r['task_id'], r['condition'])].append(r)
    tasks = sorted({t for t, _ in by})
    out.write('## RQ1: generation results per task\n\n')
    out.write('| Task | Condition | n | Compiled | R_syn [95% CI] | Passed | R_fun [95% CI] | pass@1 | pass@5 |\n')
    out.write('|---|---|---|---|---|---|---|---|---|\n')
    tables = []
    for t in tasks:
        cells = {}
        for cond in ('workflow', 'baseline'):
            rs = by.get((t, cond), [])
            n = len(rs)
            ks = sum(b(r['compiled']) for r in rs)
            kp = sum(b(r['scene_test_pass']) for r in rs)
            cells[cond] = (kp, n - kp)
            ws, wf = wilson(ks, n), wilson(kp, n)
            out.write('| %s | %s | %d | %d | %.2f [%.2f, %.2f] | %d | %.2f [%.2f, %.2f] | %.2f | %s |\n' % (
                t, cond, n, ks, ks / n if n else float('nan'), ws[0], ws[1], kp, kp / n if n else float('nan'),
                wf[0], wf[1], pass_at_k(n, kp, 1) if n else float('nan'),
                '%.2f' % pass_at_k(n, kp, 5) if n >= 5 else 'n/a'))
        (a, bb), (c, d) = cells['workflow'], cells['baseline']
        tables.append((a, bb, c, d))
        out.write('| %s | Fisher exact (workflow vs baseline, R_fun) | | | | | p = %.4f | | |\n' % (t, fisher_exact(a, bb, c, d)))
    chi2, p, orr = cmh(tables)
    out.write('\nPrimary test of RQ1 - Cochran-Mantel-Haenszel test over tasks (R_fun, continuity-corrected): '
              'chi2 = %.3f, p = %.4f, MH common odds ratio = %.2f. The per-task Fisher tests above are descriptive.\n\n'
              % (chi2, p, orr))

    out.write('## RQ2: A2 model-conformance verdict vs NuSMV verdict on the A1 GRAFCET (tank tasks)\n\n')
    # criterion (iii) of Section 4: the A2 model-conformance verdict on the GRAFCET model generated in the A1 lane
    pairs = [(b(r['a2_grafcet_consistent']), b(r['nusmv_all_hold'])) for r in rows
             if r.get('nusmv_all_hold', '').strip() not in ('', 'NA')
             and r.get('a2_grafcet_consistent', '').strip() not in ('', 'NA')]
    n11 = sum(1 for x, y in pairs if x and y)
    n10 = sum(1 for x, y in pairs if x and not y)
    n01 = sum(1 for x, y in pairs if not x and y)
    n00 = sum(1 for x, y in pairs if not x and not y)
    k, ci, po = cohen_kappa(n11, n10, n01, n00)
    out.write('| | NuSMV: all hold | NuSMV: violation |\n|---|---|---|\n')
    out.write('| A2 accepts | %d | %d |\n| A2 rejects | %d | %d |\n\n' % (n11, n10, n01, n00))
    fa = wilson(n10, n11 + n10)
    out.write('Primary measure - A2 false accepts (A2 accepts, NuSMV finds a violation): %d of %d accepted samples = %.2f '
              '[Wilson 95%% CI %.2f, %.2f]\n\n' % (n10, n11 + n10, n10 / (n11 + n10) if n11 + n10 else float('nan'),
                                                    fa[0], fa[1]))
    out.write('Secondary: agreement = %.2f; Cohen kappa = %.2f [%.2f, %.2f] (kappa is depressed when one verdict '
              'dominates)\n\n' % (po, k, ci[0], ci[1]))
    cls = defaultdict(int)
    for r in rows:
        if r.get('discrepancy_class', '').strip():
            cls[r['discrepancy_class'].strip()] += 1
    if cls:
        out.write('Discrepancy classes reported by A2: ' + ', '.join('%s = %d' % kv for kv in sorted(cls.items())) + '\n\n')


def report_gvm(rows, out):
    """Secondary, descriptive (no test): the A1 and A2 GRAFCET models of the workflow samples run as the Python and
    C++ programs of the GVM in the registered situations (gvm/gvm_scene.py).  NA counts as not passed."""
    wf = [r for r in rows if r['condition'] == 'workflow']
    out.write('## GRAFCET models run as GVM programs (secondary, descriptive; gvm/gvm_scene.py)\n\n')
    if not any(r.get('gvm_py_scene_pass', '').strip() for r in wf):
        out.write('No results in runs.csv yet (python3 gvm/gvm_scene.py runs.csv --base DIR --write).\n\n')
        return
    out.write('| Task | Lane | n | Python passed | R_gvm [95% CI] | C++ passed | NA | E3 > 0 |\n|---|---|---|---|---|---|---|---|\n')
    val = lambda r, c: r.get(c, '').strip()
    for t in sorted({r['task_id'] for r in wf}):
        rs = [r for r in wf if r['task_id'] == t]
        n = len(rs)
        for lane, pre in (('A1', ''), ('A2', 'a2_')):
            kp = sum(val(r, pre + 'gvm_py_scene_pass') == '1' for r in rs)
            kc = sum(val(r, pre + 'gvm_cpp_scene_pass') == '1' for r in rs)
            na = sum(val(r, pre + 'gvm_py_scene_pass') in ('', 'NA') for r in rs)
            e3 = sum(val(r, pre + 'gvm_e3') not in ('', 'NA', '0') for r in rs)
            lo, hi = wilson(kp, n)
            out.write('| %s | %s | %d | %d | %.2f [%.2f, %.2f] | %d | %d | %d |\n' % (
                t, lane, n, kp, kp / n if n else float('nan'), lo, hi, kc, na, e3))
    cell = defaultdict(int)
    for r in wf:
        cell[(val(r, 'gvm_py_scene_pass') == '1', b(r['scene_test_pass']))] += 1
    out.write('\nA1 GRAFCET (GVM, Python) against the A1 ST program of the same sample (scene_test_pass):\n\n')
    out.write('| | ST program passed | ST program failed |\n|---|---|---|\n')
    out.write('| GRAFCET passed | %d | %d |\n| GRAFCET failed or NA | %d | %d |\n\n' % (
        cell[(True, True)], cell[(True, False)], cell[(False, True)], cell[(False, False)]))


def table9(rows, path):
    """Results table of the paper (Section 5.5) as CSV: one row per task and condition, then the primary test."""
    by = defaultdict(list)
    for r in rows:
        by[(r['task_id'], r['condition'])].append(r)
    out = csv.writer(open(path, 'w', encoding='utf-8', newline=''))
    out.writerow(['Task', 'Condition', 'n', 'Compiled', 'R_syn', 'R_syn 95% CI', 'Passed', 'R_fun', 'R_fun 95% CI',
                  'pass@1', 'pass@5'])
    tables = []
    for t in sorted({t for t, _ in by}):
        cells = {}
        for cond in ('workflow', 'baseline'):
            rs = by.get((t, cond), [])
            n = len(rs)
            ks = sum(b(r['compiled']) for r in rs)
            kp = sum(b(r['scene_test_pass']) for r in rs)
            cells[cond] = (kp, n - kp)
            ws, wf = wilson(ks, n), wilson(kp, n)
            out.writerow([t, cond, n, ks, '%.2f' % (ks / n) if n else '', '[%.2f, %.2f]' % ws if n else '', kp,
                          '%.2f' % (kp / n) if n else '', '[%.2f, %.2f]' % wf if n else '',
                          '%.2f' % pass_at_k(n, kp, 1) if n else '', '%.2f' % pass_at_k(n, kp, 5) if n >= 5 else ''])
        (a, bb), (c, d) = cells['workflow'], cells['baseline']
        tables.append((a, bb, c, d))
        out.writerow([t, 'Fisher exact p (descriptive)', '', '', '', '', '', '%.4f' % fisher_exact(a, bb, c, d), '', '', ''])
    chi2, p, orr = cmh(tables)
    out.writerow(['All tasks', 'Cochran-Mantel-Haenszel (primary)', '', '', '', '', '',
                  'chi2 = %.3f, p = %.4f' % (chi2, p), 'MH odds ratio = %.2f' % orr, '', ''])


def selftest():
    global SS
    assert SS is not None, 'selftest compares against scipy'
    print('SELFTEST on synthetic inputs (not study results)')
    lo, hi = wilson(10, 20)
    assert abs(lo - 0.2993) < 1e-3 and abs(hi - 0.7007) < 1e-3, (lo, hi)
    print('  Wilson(10, 20) = [%.4f, %.4f]  ok' % (lo, hi))
    assert abs(pass_at_k(20, 5, 1) - 0.25) < 1e-12
    print('  pass@1(n=20, c=5) = 0.25  ok')
    keep = SS
    for tab in ([8, 2, 1, 5], [12, 8, 5, 15], [20, 0, 14, 6]):
        SS = keep
        ref = keep.fisher_exact([[tab[0], tab[1]], [tab[2], tab[3]]]).pvalue
        SS = None
        mine = fisher_exact(*tab)
        assert abs(ref - mine) < 1e-9, (tab, ref, mine)
    print('  Fisher exact fallback matches scipy on 3 tables  ok')
    chi2, p, orr = cmh([(15, 5, 9, 11), (12, 8, 7, 13), (18, 2, 13, 7)])
    # hand check of the first stratum: E = 20*24/40 = 12, V = 20*20*24*16/(40*40*39)
    assert chi2 > 0 and 0 < p < 1
    print('  CMH: chi2 = %.3f, p = %.4f, OR_MH = %.2f (computed; formula checked by hand)' % (chi2, p, orr))
    k, ci, po = cohen_kappa(20, 5, 10, 15)
    assert abs(k - 0.4) < 1e-12, k
    print('  Cohen kappa(20, 5, 10, 15) = %.2f  ok' % k)
    print('SELFTEST passed')


def main():
    if sys.argv[1:] == ['--selftest']:
        selftest()
        return
    args = sys.argv[1:]
    t9 = None
    if '--table9' in args:
        i = args.index('--table9')
        t9 = args[i + 1]
        del args[i:i + 2]
    out = sys.stdout
    out.write('# Analysis report\n\n')
    rows = list(csv.DictReader(open(args[0], encoding='utf-8')))
    report_runs(rows, out)
    report_gvm(rows, out)
    if t9:
        table9(rows, t9)
        out.write('Results table (Section 5.5) written to %s\n\n' % t9)


if __name__ == '__main__':
    main()
