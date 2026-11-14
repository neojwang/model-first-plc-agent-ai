#!/usr/bin/env python3
"""Scene tests of the GRAFCET models: each GRAFCET runs as the Python and the C++ program of the GRAFCET virtual machine
(GVM) in the closed loops of exec/scene_sim.py.

Purpose.  The GRAFCET models of the workflow samples (A1 and A2 lanes) are executed as GVM programs:
gvm/grafcet2gvm.py generates the Python module and the C++ header from the GRAFCET description, and both run the
registered situations of exec/scene_tests_en.md against the scene models of exec/scene_sim.py.  The ST programs of the samples are tested by scene_sim.py as before;
this test asks whether the GRAFCET model itself, executed exactly, meets the same situations.

Method.  One PLC scan (20 ms) is one GVM tick: one evolution of the GRAFCET to a stable situation, with the semantics
that NuSMV checks (nusmv/grafcet2smv.py).  The located inputs and outputs of the task card are bound to the identifier
vocabulary of the task card, the same for every GRAFCET:
  * start is the rising edge of StartCommand (TRUE only in the scan in which the button is pressed); stop is
    StopCommand; sensor_a and sensor_b are the two sensors of T1;
  * r is the level region: from LSH and LSHH in T2 and T3 (HIGH when LSHH, MID when only LSH, LOW otherwise), from the
    level meter in T4 (LOW for h < h_target = 0.8 h_span, MID for h_target <= h < h_max = 0.9 h_span, HIGH above);
    LSH and LSHH are the derived inputs of exec/taskio.py;
  * an owned condition is measured on the activity of the step that the GRAFCET names as its owner, with the preset it
    names (a parameter of the task card, with the value of the situation in exec/set_params.py; t_h = 10 s):
    timer_done and ton_q as an on-delay timer (TON) with IN := activity of the owner, tof_q as TRUE until the owner has
    been active for the preset (the off-delay output measured by the pause step, rule 5 of the schema), settled as an
    on-delay timer with IN := activity of the owner AND |e| <= eps (eps = 0.02 h_span).  As in the GVM, a condition
    takes its neutral value until its owner has been active since the start of the evolution.  A timer condition
    used in a guard but not declared in "owned" is held FALSE;
  * outputs: T1 conveyor; T2 and T3 fill_valve and discharge_valve; in T4, fill_valve TRUE lets a PID controller drive
    the fill valve and discharge_valve TRUE holds the discharge valve at 40 % (task card), the PID being the algorithm
    of pilot/reference/T4_ref.st (integral reset on entry, clamping to 0-100 % with integration suspended while
    clamped) with the gains of the situation; as in that program, the level, the error, the band check and the PID
    are computed in REAL (32-bit) arithmetic, rounded after every operation.  An output of the task card that the
    GRAFCET does not give is held FALSE.
Step 0.  The scene tests take a new start that opens the output, and StopCommand that closes it, as evidence that an
ST program has returned to step 0 (exec/scene_tests_en.md); the GVM programs get the same probe.  The one exception
is a new start while the level already meets the end condition of the started step (LSHH on in T2, LSH on in T3,
h >= h_max in T4; at the probes of T2 (b) and T3 (a)): in a GRAFCET this start is a transient evolution, the step is
left in the same evolution and its continuous action is not executed, so no output opens.  There the evidence is read
from the situation, which is the whole state of a GVM program: it must be the initial situation, with the output at
0, before the new start and again after the start and StopCommand of the probe, so that a new cycle runs as the first
one did.
The verdict of a program is 1 only if every registered situation passes.  E3 counts the ticks of the Python closed
loops in which the C++ program, given the same inputs, reaches a different situation, stability flag, or outputs;
the C++ program also runs its own closed loops.  NA: the GRAFCET is missing, is not a JSON object, or uses names or
constructs outside the schema of exec/prompts/templates/_schema.md (no program can be generated); the reason is kept.

Usage:
  python3 gvm/gvm_scene.py --reference [--log gvm/scene_log.txt]   # reference GRAFCETs, seeded faults, variants
  python3 gvm/gvm_scene.py --file MODEL.json --task T3              # one GRAFCET
  python3 gvm/gvm_scene.py runs.csv --base ARTIFACT_DIR [--write]   # A1 and A2 GRAFCETs of every workflow sample
  python3 gvm/gvm_scene.py --selftest
Python 3.8 or later, standard library only; g++ with C++17 for the C++ programs (without g++ they are NA).
"""
import argparse
import copy
import csv
import ctypes
import datetime
import hashlib
import importlib.util
import json
import math
import os
import platform
import re
import shutil
import struct
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True   # keep the kit folders free of __pycache__
HERE = os.path.dirname(os.path.abspath(__file__))
KIT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(KIT, 'nusmv'))
sys.path.insert(0, os.path.join(KIT, 'exec'))
import grafcet2gvm as GEN  # noqa: E402
import grafcet2smv as G  # noqa: E402
from taskio import TASK_IO  # noqa: E402


def _load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


SIM = _load(os.path.join(KIT, 'exec', 'scene_sim.py'), 'scene_sim')
SETP = SIM.set_params

TS = 0.02
FULL_SCALE, H_SP, H_MAX, EPS, T_H, U_D = 1000, 0.8, 0.9, 0.02, 10.0, 0.4
KIND = {'timer_done': 'on', 'ton_q': 'on', 'tof_q': 'off', 'settled': 'hold'}
PRESETS = {'T1': {}, 'T2': {'timerduration'}, 'T3': {'ton_duration', 'tof_duration'}, 'T4': {'t_h'}}
LOC_IN = {'T1': {'sensor_a': '%IX100.0', 'sensor_b': '%IX100.1'},
          'T2': {'start': '%IX100.0', 'stop': '%IX100.1', 'lsh': '%IX100.2', 'lshh': '%IX100.3'},
          'T3': {'start': '%IX100.0', 'stop': '%IX100.1', 'lsh': '%IX100.2', 'lshh': '%IX100.3'},
          'T4': {'start': '%IX100.0', 'stop': '%IX100.1', 'level': '%IW100'}}
LOC_OUT = {'T1': {'conveyor': '%QX100.0'},
           'T2': {'fill_valve': '%QX100.0', 'discharge_valve': '%QX100.1'},
           'T3': {'fill_valve': '%QX100.0', 'discharge_valve': '%QX100.1'},
           'T4': {'fill_valve': '%QW100', 'discharge_valve': '%QW101'}}
STEP_RE = re.compile(r'^x[A-Za-z0-9_]*$')
RESERVED = {'xor', 'xor_eq'}         # C++ alternative tokens that a step name could spell
COLS = ['gvm_py_scene_pass', 'gvm_cpp_scene_pass', 'gvm_e3', 'a2_gvm_py_scene_pass', 'a2_gvm_cpp_scene_pass',
        'a2_gvm_e3']
WRAP = r'''#include "%(name)s_gvm.hpp"
namespace G = gvm_%(name)s;
static G::GVM g;
#define API extern "C" __attribute__((visibility("default")))
API void gvm_reset(void) { g.reset(); }
API int gvm_tick(const int *in, unsigned char *sit, unsigned char *out) {
  G::Inputs i{};
  for (int k = 0; k < G::N_INPUTS; ++k) i[k] = in[k];
  const bool st = g.tick(i);
  for (int s = 0; s < G::N_STEPS; ++s) sit[s] = g.c[s] ? 1 : 0;
  const G::Outputs o = G::outputs(g.c);
  for (int k = 0; k < G::N_OUTPUTS; ++k) out[k] = o[k] ? 1 : 0;
  return st ? 1 : 0;
}
'''


class NA(Exception):
    """No program can be generated from this GRAFCET."""


# ---------------------------------------------------------------- description

def gvm_spec(task, d, name):
    """GRAFCET JSON of a sample -> description for grafcet2gvm.py, with the task I/O of exec/taskio.py."""
    io = TASK_IO[task]
    if not isinstance(d, dict):
        raise NA('not a JSON object')
    for key in ('graphs', 'transitions', 'outputs'):
        if key not in d:
            raise NA('no "%s"' % key)
    try:
        graphs = [{'name': str(g['name']), 'steps': [str(x) for x in g['steps']], 'initial': [str(x) for x in g['initial']]}
                  for g in d['graphs']]
    except (TypeError, KeyError) as e:
        raise NA('graphs: %s' % e)
    steps = [x for g in graphs for x in g['steps']]
    for x in steps:
        if not STEP_RE.match(x) or x in RESERVED:
            raise NA('step name %r is outside rule 1 of the schema' % x)
    if len(set(steps)) != len(steps):
        raise NA('a step appears twice')
    if not any(g['initial'] for g in graphs) or any(set(g['initial']) - set(g['steps']) for g in graphs):
        raise NA('initial steps missing or not in their graph')
    allowed = set(io['inputs']) | set(io['derived']) | set(steps)
    trans = []
    try:
        for k, t in enumerate(d['transitions'], 1):
            frm, to = [str(x) for x in t['from']], [str(x) for x in t['to']]
            if not frm or not to or (set(frm) | set(to)) - set(steps):
                raise NA('transition %s: unknown or missing steps' % t.get('id', k))
            node = G.parse(str(t['guard']))
            bad = G.names(node) - allowed
            if bad:
                raise NA('unknown identifier in a guard: %s' % ', '.join(sorted(bad)))
            trans.append({'id': 't%d' % k, 'from': frm, 'to': to, 'guard': str(t['guard'])})
    except (TypeError, KeyError, SyntaxError, ValueError, AssertionError) as e:
        if isinstance(e, NA):
            raise
        raise NA('transitions: %s' % e)
    if not isinstance(d['outputs'], dict):
        raise NA('"outputs" is not an object')
    outputs, notes = {}, []
    for o in io['outputs']:
        if o in d['outputs']:
            try:
                bad = G.names(G.parse(str(d['outputs'][o]))) - set(steps)
            except (SyntaxError, ValueError, AssertionError) as e:
                raise NA('output %s: %s' % (o, e))
            if bad:
                raise NA('output %s uses names that are not steps: %s' % (o, ', '.join(sorted(bad))))
            outputs[o] = str(d['outputs'][o])
        else:
            outputs[o] = 'FALSE'
            notes.append('output %s not given: held FALSE' % o)
    extra = sorted(set(d['outputs']) - set(io['outputs']))
    if extra:
        notes.append('outputs outside the task card ignored: %s' % ', '.join(extra))
    owned = {}
    if not isinstance(d.get('owned') or {}, dict) or not isinstance(d.get('forcing') or [], list):
        raise NA('"owned" is not an object or "forcing" is not a list')
    for c, o in (d.get('owned') or {}).items():
        if c not in io['inputs'] or c not in KIND:
            raise NA('owned condition %s is not a timer or hold condition of the task card' % c)
        try:
            step, neutral, preset = str(o['step']), o['neutral'], str(o['preset'])
        except (TypeError, KeyError) as e:
            raise NA('owned condition %s: %s' % (c, e))
        if step not in steps:
            raise NA('owned condition %s: unknown step %s' % (c, step))
        if not isinstance(neutral, bool):
            raise NA('owned condition %s: neutral is not true or false' % c)
        if preset.lower() not in PRESETS[task]:
            raise NA('owned condition %s: preset %s is not a parameter of the task card' % (c, preset))
        owned[c] = {'step': step, 'neutral': neutral, 'preset': preset}
    used = set()
    for t in trans:
        used |= G.names(G.parse(t['guard']))
    for c in sorted((used & set(KIND)) - set(owned)):
        notes.append('%s used in a guard but not declared in "owned": held FALSE' % c)
    forcing = []
    gsteps = {g['name']: g['steps'] for g in graphs}
    for fo in d.get('forcing') or []:
        try:
            by, gname, sit = str(fo['by']), str(fo['graph']), [str(x) for x in fo['situation']]
        except (TypeError, KeyError) as e:
            raise NA('forcing: %s' % e)
        if by not in steps or gname not in gsteps or set(sit) - set(gsteps[gname]):
            raise NA('forcing order of %s: unknown step or graph' % by)
        forcing.append({'by': by, 'graph': gname, 'situation': sit})
    spec = {'name': name, 'inputs': io['inputs'], 'derived': io['derived'], 'owned': owned,
            'events': io.get('events', []), 'graphs': graphs, 'transitions': trans, 'forcing': forcing,
            'outputs': outputs}
    try:                                  # the generator itself must accept the description in both languages
        desc = GEN.Desc(spec)
        GEN.gen_py(desc, '')
        GEN.gen_hpp(desc, '')
    except (AssertionError, KeyError, NameError, ValueError, SyntaxError, TypeError) as e:
        raise NA('description: %s %s' % (type(e).__name__, e))
    return spec, notes


# ---------------------------------------------------------------- the two programs

class PyCore:
    lang = 'Python'

    def __init__(self, gdir, name):
        mod = _load(os.path.join(gdir, name + '_gvm.py'), 'gvm_%s_%d' % (name, id(self)))
        self.g, self.inputs, self.steps, self.outputs = mod.GVM(), list(mod.INPUTS), list(mod.STEPS), list(mod.OUTPUTS)

    def reset(self):
        self.g.reset()

    def tick(self, vec):
        c, st, o = self.g.tick(vec)
        return tuple(bool(x) for x in c), bool(st), tuple(bool(x) for x in o)


class CppCore:
    lang = 'C++'

    def __init__(self, gdir, name, work):
        src = os.path.join(work, 'wrap_%s.cpp' % name)
        so = os.path.join(work, 'libgvm_%s.so' % name)
        with open(src, 'w', encoding='utf-8') as f:
            f.write(WRAP % {'name': name})
        r = subprocess.run(['g++', '-std=c++17', '-O2', '-fPIC', '-shared', '-fvisibility=hidden', '-I', gdir, src, '-o', so],
                           capture_output=True, text=True)
        if r.returncode != 0:
            raise RuntimeError('g++: ' + (r.stdout + r.stderr).replace(work, '<tmp>').strip()[-300:])
        with open(os.path.join(gdir, name + '_gvm_io.json'), encoding='utf-8') as f:
            io = json.load(f)
        self.inputs, self.steps, self.outputs = io['inputs'], io['steps'], io['outputs']
        self.lib = ctypes.CDLL(so, mode=os.RTLD_LOCAL)
        self.lib.gvm_tick.restype = ctypes.c_int
        self.ib = (ctypes.c_int * max(1, len(self.inputs)))()
        self.sb = (ctypes.c_ubyte * max(1, len(self.steps)))()
        self.ob = (ctypes.c_ubyte * max(1, len(self.outputs)))()

    def reset(self):
        self.lib.gvm_reset()

    def tick(self, vec):
        for k, v in enumerate(vec):
            self.ib[k] = int(v)
        st = self.lib.gvm_tick(self.ib, self.sb, self.ob)
        return (tuple(bool(self.sb[k]) for k in range(len(self.steps))), bool(st),
                tuple(bool(self.ob[k]) for k in range(len(self.outputs))))


def gpp_version():
    try:
        return subprocess.run(['g++', '--version'], capture_output=True, text=True).stdout.splitlines()[0]
    except (OSError, IndexError):
        return None


# ---------------------------------------------------------------- the PLC seen by the scene tests

def seconds(kind, value):
    if kind == 'REAL':
        return float(value)
    m = re.match(r'(?i)^T#(\d+(?:\.\d+)?)(ms|s)$', value.strip())
    if not m:
        raise ValueError('time literal %s' % value)
    return float(m.group(1)) / (1000.0 if m.group(2).lower() == 'ms' else 1.0)


def situation_params(task, case):
    p = {k.lower(): seconds(kind, v) for k, (kind, v) in SETP.SCENARIOS.get((task, case), {}).items()}
    if task == 'T4':
        p['t_h'] = T_H
    return p


def f32(x):
    """x rounded to an IEC 61131-3 REAL (IEEE 754 single precision)."""
    return struct.unpack('<f', struct.pack('<f', x))[0]


R_SP, R_MAX, R_EPS, R_UD, R_FS = f32(H_SP), f32(H_MAX), f32(EPS), f32(U_D), f32(float(FULL_SCALE))


def real_to_int(x):
    return int(math.floor(x + 0.5)) if x >= 0 else -int(math.floor(-x + 0.5))


class GvmPLC:
    """The interface of scene_sim.PLC (reset, set, get, scan, ts, missing) around a GVM program and the binding."""

    def __init__(self, task, core, spec, params, record=False):
        self.task, self.core, self.p, self.record = task, core, params, record
        self.ts = TS
        self.missing = set()
        self.enum = {n: list(v) for n, v in spec['inputs'].items() if v != 'boolean'}
        self.owned = {c: (o['step'], KIND[c], params[o['preset'].lower()]) for c, o in spec['owned'].items()}
        self.init = {x for g in spec['graphs'] for x in g['initial']}
        self.rec, self.unstable, self.o = [], 0, {}
        self.init_sit = tuple(x in self.init for x in core.steps)

    def reset(self):
        self.core.reset()
        self.img = {}
        self.out = {loc: 0 for loc in LOC_OUT[self.task].values()}
        self.j, self.prev_start = 0, 0
        self.active = set(self.init)
        self.sit = self.init_sit
        self.t_on = {c: None for c in self.owned}
        self.i_term = self.e_prev = 0.0
        self.fill_prev = False
        self.rec, self.unstable = [], 0

    def set(self, loc, v):
        self.img[loc] = int(v)

    def get(self, loc):
        if loc.startswith('%I'):
            return self.img.get(loc, 0)
        return self.out.get(loc, 0)

    def _in(self, key):
        return self.img.get(LOC_IN[self.task][key], 0)

    def scan(self):
        task, j, ts = self.task, self.j, self.ts
        val = {}
        if task == 'T1':
            val['sensor_a'], val['sensor_b'] = self._in('sensor_a'), self._in('sensor_b')
        else:
            btn = self._in('start')
            val['start'] = 1 if (btn and not self.prev_start) else 0
            val['stop'] = self._in('stop')
            if task == 'T4':
                h = f32(f32(float(self._in('level'))) / R_FS)
                e = f32(R_SP - h)
                val['r'] = 2 if h >= R_MAX else (1 if h >= R_SP else 0)
            else:
                e = 0.0
                val['r'] = 2 if self._in('lshh') else (1 if self._in('lsh') else 0)
            for c, (s, kind, pt) in self.owned.items():
                cond = s in self.active and (kind != 'hold' or abs(e) <= R_EPS)
                if cond:
                    if self.t_on[c] is None:
                        self.t_on[c] = j
                    done = (j - self.t_on[c]) * ts >= pt - 1e-9
                else:
                    self.t_on[c], done = None, False
                val[c] = (0 if done else 1) if kind == 'off' else (1 if done else 0)
            self.prev_start = btn
        vec = [val.get(n, 0) for n in self.core.inputs]
        sit, stable, outs = self.core.tick(vec)
        if self.record:
            self.rec.append((tuple(vec), sit, stable, outs))
        self.unstable += not stable
        self.sit = sit
        self.active = {x for x, a in zip(self.core.steps, sit) if a}
        o = self.o = dict(zip(self.core.outputs, outs))   # GRAFCET outputs of this scan (gvm/st_match.py)
        if task == 'T4':
            fill, dis = o.get('fill_valve', False), o.get('discharge_valve', False)
            if fill:
                kp, ti, td, rts = f32(self.p['kp']), f32(self.p['ti']), f32(self.p['td']), f32(ts)
                if not self.fill_prev:
                    self.i_term, self.e_prev = 0.0, e
                d_term = f32(f32(f32(kp * td) * f32(e - self.e_prev)) / rts) if rts > 0 else 0.0
                u_raw = f32(f32(f32(kp * e) + self.i_term) + d_term)
                if u_raw > 1.0:
                    u = 1.0
                elif u_raw < 0.0:
                    u = 0.0
                else:
                    u = u_raw
                    if ti > 0:
                        self.i_term = f32(self.i_term + f32(f32(f32(kp * rts) / ti) * e))
                self.e_prev = e
                self.out['%QW100'] = real_to_int(f32(u * R_FS))
            else:
                self.out['%QW100'] = 0
            self.out['%QW101'] = real_to_int(f32(R_UD * R_FS)) if dis else 0
            self.fill_prev = fill
        else:
            for name, loc in LOC_OUT[task].items():
                self.out[loc] = 1 if o.get(name, False) else 0
        self.j += 1


def _restart_gvm(b, loc):
    """Step-0 evidence for a GVM program (see Step 0 above); the ST programs keep scene_sim._restart."""
    if not isinstance(b.plc, GvmPLC):
        return _restart_st(b, loc)
    p, task = b.plant, b.plc.task
    ended = (task == 'T2' and p.lshh()) or (task == 'T3' and p.lsh()) or (task == 'T4' and p.x >= H_MAX)
    if not ended:
        return _restart_st(b, loc)
    before = b.plc.sit == b.plc.init_sit and b.plc.get(loc) == 0
    b.press('start', b.t + 1.0)
    b.run_until(lambda: b.plc.get(loc) > 0, b.t + 2.0)
    b.press('stop', b.t + 0.5)
    b.run_until(lambda: False, b.t + 1.5)
    return before and b.plc.sit == b.plc.init_sit and b.plc.get(loc) == 0


_restart_st, SIM._restart = SIM._restart, _restart_gvm


# ---------------------------------------------------------------- running a GRAFCET

def run_program(task, spec, core, variant=None, record=False):
    """All registered situations of the task; returns (verdict, lines, per-situation results, recordings)."""
    verdict, lines, res, recs = 1, [], {}, {}
    for case in SIM.SITUATIONS[task]:
        plc = GvmPLC(task, core, spec, situation_params(task, case), record)
        ok, detail, metrics = SIM.run_situation(plc, task, case, variant or {})
        verdict &= bool(ok)
        res[case] = {'pass': bool(ok), 'detail': detail, 'unstable_ticks': plc.unstable}
        recs[case] = plc.rec
        lines.append('%s (%s): %s - %s%s' % (task, case, 'pass' if ok else 'FAIL', detail,
                                             '; %d unstable tick(s)' % plc.unstable if plc.unstable else ''))
    return int(verdict), lines, res, recs


def e3(core, recs):
    """Ticks of the recorded closed loops in which core reaches another situation, stability flag, or outputs."""
    n = 0
    for rec in recs.values():
        core.reset()
        for vec, sit, st, outs in rec:
            n += core.tick(list(vec)) != (sit, st, outs)
    return n


def test_grafcet(task, d, label, work, variants=None):
    """Generate the two programs from one GRAFCET and run them.  Returns a result dictionary."""
    name = re.sub(r'[^A-Za-z0-9_]', '_', label)[:40]
    out = {'label': label, 'task': task, 'py': 'NA', 'cpp': 'NA', 'e3': 'NA', 'reason': '', 'notes': [], 'log': [],
           'desc_sha256': ''}
    try:
        spec, notes = gvm_spec(task, d, name)
    except NA as e:
        out['reason'] = str(e)
        out['log'].append('NA: %s' % e)
        return out
    out['notes'] = notes
    out['desc_sha256'] = GEN.desc_sha(spec)
    gdir = os.path.join(work, name)
    GEN.generate(None, gdir, spec=spec)
    py = PyCore(gdir, name)
    v, lines, res, recs = run_program(task, spec, py, record=True)
    out['py'], out['py_situations'] = v, res
    out['log'] += ['Python: ' + l for l in lines]
    if variants:
        out['sensitivity'] = {}
        for vlabel, var in sorted(variants.items()):
            vv, _, vres, _ = run_program(task, spec, PyCore(gdir, name), var)
            out['sensitivity'][vlabel] = sum(r['pass'] for r in vres.values())
    if gpp_version() is None:
        out['reason'] = 'C++: g++ not found'
        return out
    try:
        cpp = CppCore(gdir, name, work)
    except RuntimeError as e:
        out['reason'] = 'C++: %s' % e
        return out
    out['e3'] = e3(cpp, recs)
    v2, lines2, res2, _ = run_program(task, spec, cpp)
    out['cpp'], out['cpp_situations'] = v2, res2
    out['log'] += ['C++: ' + l for l in lines2]
    out['log'].append('E3 (C++ against Python on the Python closed loops): %d tick(s)' % out['e3'])
    return out


def load_json(path):
    with open(path, encoding='utf-8', errors='replace') as f:
        return json.load(f)


# ---------------------------------------------------------------- reference GRAFCETs and seeded faults

def _guard(d, tid, g):
    for t in d['transitions']:
        if t['id'] == tid:
            t['guard'] = g
    return d


def _set(path, value):
    def f(d):
        node = d
        for k in path[:-1]:
            node = node[k]
        node[path[-1]] = value
        return d
    return f


FAULTS = [   # (task, label, mutation of the reference): every fault must fail at least one registered situation
    ('T1', 'conveyor on step x0 instead of x1', _set(['outputs', 'conveyor'], 'x0')),
    ('T1', 'stop at sensor B removed (guard FALSE)', lambda d: _guard(d, 't2', 'FALSE')),
    ('T2', 'LSHH removed from the end of filling', lambda d: _guard(d, 't2', 'stop | timer_done')),
    ('T2', 'stop removed from the end of filling', lambda d: _guard(d, 't2', 'timer_done | LSHH')),
    ('T2', 'timer owned by step x0', _set(['owned', 'timer_done', 'step'], 'x0')),
    ('T3', 'tof_q neutral FALSE (rule 5 violated)', _set(['owned', 'tof_q', 'neutral'], False)),
    ('T3', 'ton_q owned by the pause step', _set(['owned', 'ton_q', 'step'], 'x22')),
    ('T3', 'LSH removed from the end of filling', lambda d: _guard(d, 't2', 'stop')),
    ('T4', 'r = HIGH removed from the end of regulation', lambda d: _guard(d, 't2', 'stop | settled')),
    ('T4', 'settled neutral TRUE', _set(['owned', 'settled', 'neutral'], True)),
    ('T4', 'discharge valve never held', _set(['outputs', 'discharge_valve'], 'FALSE')),
]


def reference(log_path):
    lines = []
    say = lambda s='': (lines.append(s), print(s))
    tool_sha = lambda p: hashlib.sha256(open(p, 'rb').read()).hexdigest()[:16]
    say('GVM scene tests of the reference GRAFCETs and seeded faults (gvm/gvm_scene.py --reference)')
    say('date (UTC): %s' % datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%d %H:%M'))
    say('Python %s; %s; %s' % (platform.python_version(), gpp_version() or 'g++ not found', SIM.SCENE_MODEL))
    say('SHA-256 (first 16): gvm_scene.py %s, grafcet2gvm.py %s, grafcet2smv.py %s, scene_sim.py %s' % (
        tool_sha(os.path.abspath(__file__)), tool_sha(os.path.join(HERE, 'grafcet2gvm.py')),
        tool_sha(os.path.join(KIT, 'nusmv', 'grafcet2smv.py')), tool_sha(os.path.join(KIT, 'exec', 'scene_sim.py'))))
    say()
    work = tempfile.mkdtemp(prefix='gvm_scene_')
    ok_all = True
    try:
        say('1. Reference GRAFCETs (gvm/reference/T1-T4_ref.json): every registered situation must pass in Python and C++,')
        say('   with E3 = 0; the alternative assumptions of scene_sim.py --sensitivity are reported, not judged.')
        refs = {}
        for t in ('T1', 'T2', 'T3', 'T4'):
            path = os.path.join(HERE, 'reference', '%s_ref.json' % t)
            refs[t] = load_json(path)
            r = test_grafcet(t, refs[t], '%s_ref' % t, work, SIM.VARIANTS[t])
            good = r['py'] == 1 and r['cpp'] == 1 and r['e3'] == 0
            ok_all &= good
            say('%s_ref.json (SHA-256 %s; description %s): Python %s, C++ %s, E3 %s -> %s' % (
                t, tool_sha(path), r['desc_sha256'][:16], r['py'], r['cpp'], r['e3'], 'ok' if good else 'NOT OK'))
            for l in r['log']:
                say('   ' + l)
            for vlabel, n in sorted(r.get('sensitivity', {}).items()):
                say('   sensitivity (Python), %s: %d/%d situations pass' % (vlabel, n, len(SIM.SITUATIONS[t])))
        say()
        say('2. Seeded faults: each must fail at least one registered situation in Python and in C++, with E3 = 0.')
        for k, (t, label, mut) in enumerate(FAULTS, 1):
            d = mut(copy.deepcopy(refs[t]))
            r = test_grafcet(t, d, 'F%02d_%s' % (k, t), work)
            failed_py = [c for c, s in r.get('py_situations', {}).items() if not s['pass']]
            failed_cpp = [c for c, s in r.get('cpp_situations', {}).items() if not s['pass']]
            good = r['py'] == 0 and r['cpp'] == 0 and r['e3'] == 0
            ok_all &= good
            say('F%02d %s, %s: Python fails %s; C++ fails %s; E3 %s -> %s' % (
                k, t, label, ','.join(failed_py) or 'none', ','.join(failed_cpp) or 'none', r['e3'],
                'detected' if good else 'NOT DETECTED'))
        say()
        say('verdict: %s' % ('every reference passes, every seeded fault is detected, E3 = 0 throughout' if ok_all
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
    if not rows:
        sys.exit('%s has no rows' % a.runs)
    work = tempfile.mkdtemp(prefix='gvm_scene_')
    out_rows, n = [], 0
    try:
        for r in rows:
            if r.get('condition') != 'workflow':
                continue
            for lane, col, pre in (('A1', 'a1_grafcet_json', ''), ('A2', 'a2_grafcet_json', 'a2_')):
                rel = r.get(col, '')
                try:
                    d = load_json(os.path.join(a.base, rel))
                except (OSError, ValueError) as e:
                    res = {'py': 'NA', 'cpp': 'NA', 'e3': 'NA', 'reason': 'GRAFCET missing or not JSON (%s)' % type(e).__name__,
                           'notes': [], 'log': [], 'desc_sha256': ''}
                else:
                    res = test_grafcet(r['task_id'], d, '%s_%s' % (r['run_id'], lane), work)
                r[pre + 'gvm_py_scene_pass'], r[pre + 'gvm_cpp_scene_pass'] = str(res['py']), str(res['cpp'])
                r[pre + 'gvm_e3'] = str(res['e3'])
                out_rows.append({'run_id': r['run_id'], 'task_id': r['task_id'], 'lane': lane, 'grafcet': rel,
                                 'description_sha256': res['desc_sha256'], 'python': res['py'], 'cpp': res['cpp'],
                                 'e3': res['e3'], 'reason': res['reason'], 'notes': '; '.join(res['notes']),
                                 'situations': ' | '.join(l for l in res['log'] if not l.startswith('E3'))})
                print('%s %s: Python %s, C++ %s, E3 %s%s' % (r['run_id'], lane, res['py'], res['cpp'], res['e3'],
                                                           ' (%s)' % res['reason'] if res['reason'] else ''))
                n += 1
    finally:
        shutil.rmtree(work, ignore_errors=True)
    path = os.path.join(os.path.dirname(os.path.abspath(a.runs)), 'gvm_runs.csv')
    with open(path, 'w', encoding='utf-8', newline='') as f:
        w = csv.DictWriter(f, fieldnames=list(out_rows[0].keys()) if out_rows else ['run_id'])
        w.writeheader()
        w.writerows(out_rows)
    print('%d GRAFCETs run; details in %s' % (n, path))
    if a.write:
        shutil.copyfile(a.runs, a.runs + '.bak')
        fields += [c for c in COLS if c not in fields]
        with open(a.runs, 'w', encoding='utf-8', newline='') as f:
            w = csv.DictWriter(f, fieldnames=fields)
            w.writeheader()
            w.writerows(rows)
        print('updated', a.runs, '(previous version kept as %s.bak)' % a.runs)
    return 0


# ---------------------------------------------------------------- self-test

def selftest():
    work = tempfile.mkdtemp(prefix='gvm_scene_')
    ok = True

    def check(cond, what):
        nonlocal ok
        ok &= bool(cond)
        print('%s  %s' % ('ok  ' if cond else 'FAIL', what))
    try:
        refs = {t: load_json(os.path.join(HERE, 'reference', '%s_ref.json' % t)) for t in ('T1', 'T2', 'T3', 'T4')}
        for t, d in refs.items():
            spec, _ = gvm_spec(t, d, 's_' + t)
            gdir = os.path.join(work, 's_' + t)
            GEN.generate(None, gdir, spec=spec)
            v, _, _, _ = run_program(t, spec, PyCore(gdir, 's_' + t))
            check(v == 1, 'reference %s passes every situation (Python)' % t)
        for t, label, mut in (FAULTS[0], FAULTS[2], FAULTS[5], FAULTS[8]):
            d = mut(copy.deepcopy(refs[t]))
            spec, _ = gvm_spec(t, d, 'f_' + t)
            gdir = os.path.join(work, 'f_' + t)
            GEN.generate(None, gdir, spec=spec)
            v, _, _, _ = run_program(t, spec, PyCore(gdir, 'f_' + t))
            check(v == 0, 'seeded fault fails (%s, %s)' % (t, label))
        bad = [('step name y1', lambda d: _set(['graphs', 0, 'steps'], ['y1', 'xE1'])(d)),
               ('step name xor', lambda d: _set(['graphs', 0, 'steps'], ['x0', 'xor'])(d)),
               ('unknown identifier in a guard', lambda d: _guard(d, 't2', 'stop | timer_done | level_high')),
               ('output over an input', _set(['outputs', 'fill_valve'], 'xE1 & !stop')),
               ('preset that is not a task parameter', _set(['owned', 'timer_done', 'preset'], 'T_fill')),
               ('equality on a Boolean input', lambda d: _guard(d, 't1', 'start = TRUE')),
               ('level region compared with an unknown value', lambda d: _guard(d, 't2', 'stop | r = FULL')),
               ('not a JSON object', lambda d: ['x0'])]
        for label, mut in bad:
            try:
                gvm_spec('T2', mut(copy.deepcopy(refs['T2'])), 'b')
                check(False, 'NA for %s' % label)
            except NA as e:
                check(True, 'NA for %s (%s)' % (label, e))
        d = copy.deepcopy(refs['T2'])
        del d['outputs']['discharge_valve']
        _, notes = gvm_spec('T2', d, 'n2')
        check(any('discharge_valve not given' in x for x in notes), 'an output that is not given is held FALSE')
        if gpp_version():
            r = test_grafcet('T3', refs['T3'], 'c_T3', work)
            check(r['py'] == 1 and r['cpp'] == 1 and r['e3'] == 0, 'T3 reference: Python 1, C++ 1, E3 0')
            r = test_grafcet('T2', FAULTS[3][2](copy.deepcopy(refs['T2'])), 'c_T2f', work)
            check(r['py'] == 0 and r['cpp'] == 0 and r['e3'] == 0, 'T2 seeded fault: Python 0, C++ 0, E3 0')
        else:
            print('skip  C++ checks (g++ not found)')
    finally:
        shutil.rmtree(work, ignore_errors=True)
    print('selftest: %s' % ('passed' if ok else 'FAILED'))
    return 0 if ok else 1


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('runs', nargs='?')
    ap.add_argument('--base', default='.')
    ap.add_argument('--write', action='store_true')
    ap.add_argument('--reference', action='store_true')
    ap.add_argument('--log', default=os.path.join(HERE, 'scene_log.txt'))
    ap.add_argument('--file')
    ap.add_argument('--task', choices=sorted(TASK_IO))
    ap.add_argument('--selftest', action='store_true')
    a = ap.parse_args()
    if a.selftest:
        return selftest()
    if a.reference:
        return reference(a.log)
    if a.file:
        if not a.task:
            sys.exit('--file needs --task')
        work = tempfile.mkdtemp(prefix='gvm_scene_')
        try:
            r = test_grafcet(a.task, load_json(a.file), os.path.splitext(os.path.basename(a.file))[0], work)
        finally:
            shutil.rmtree(work, ignore_errors=True)
        print('\n'.join(['file: %s' % a.file] + r['log'] + ['notes: ' + '; '.join(r['notes'])] * bool(r['notes']) +
                        ['verdict: Python %s, C++ %s, E3 %s%s' % (r['py'], r['cpp'], r['e3'],
                                                                 ' (%s)' % r['reason'] if r['reason'] else '')]))
        return 0 if r['py'] == 1 and r['cpp'] == 1 else 1
    if a.runs:
        return run_csv(a)
    ap.print_help()
    return 2


if __name__ == '__main__':
    sys.exit(main())
