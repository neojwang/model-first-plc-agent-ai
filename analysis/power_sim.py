#!/usr/bin/env python3
"""Sample-size calculation quoted in Section 3.2 of the paper.

  python3 power_sim.py            # about one minute; needs numpy and scipy

RQ1: Monte Carlo power of the continuity-corrected Cochran-Mantel-Haenszel test (analysis.cmh) over four
   tasks and of a single per-task Fisher exact test, for a functional pass rate of 0.50 (baseline) versus 0.70
   (workflow) in every task, n samples per task and condition, 20,000 replications, seed 20261112.
"""
import math
import os
import sys

import numpy as np
from scipy import stats

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from analysis import cmh  # noqa: E402


def main():
    rng = np.random.default_rng(20261112)
    R = 20000
    for n in (20, 30, 40):
        a = rng.binomial(n, 0.70, size=(R, 4))
        c = rng.binomial(n, 0.50, size=(R, 4))
        rej = sum(cmh([(int(a[r, k]), n - int(a[r, k]), int(c[r, k]), n - int(c[r, k])) for k in range(4)])[1] < 0.05
                  for r in range(R))
        pf = np.array([stats.fisher_exact([[int(a[r, 0]), n - int(a[r, 0])], [int(c[r, 0]), n - int(c[r, 0])]])[1]
                       for r in range(R)])
        pc, pt = rej / R, float((pf < 0.05).mean())
        print('RQ1: n = %d per task and condition: CMH power %.3f (Monte Carlo SE %.3f); single-task Fisher power '
              '%.3f (SE %.3f)' % (n, pc, math.sqrt(pc * (1 - pc) / R), pt, math.sqrt(pt * (1 - pt) / R)))


if __name__ == '__main__':
    main()
