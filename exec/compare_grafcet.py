#!/usr/bin/env python3
"""Model-conformance check of the A2 lane, criterion (iii) of Section 4 of the paper.

  python3 compare_grafcet.py T2 a1_grafcet.json a2_grafcet.json
  python3 compare_grafcet.py --selftest

Two GRAFCET models in the JSON schema of prompts/templates/_schema.md are consistent when a one-to-one
correspondence of their steps exists such that
  * graphs, initial steps, forcing orders, and timers (owning step and preset) correspond;
  * the transitions correspond one to one with the same upstream and downstream steps; and
  * each pair of corresponding receptivities, and each output, is equivalent when both are evaluated over all
    combinations of their variables (level switches LSH and LSHH are expanded to the level region r, whose three
    values are the admissible switch states).
The comparison is structural: two models that behave alike but differ in structure are reported as a discrepancy
(Section 6.1 of the paper).  The first failing check is reported as the discrepancy class.
"""
import itertools
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'nusmv'))
sys.path.insert(0, HERE)
from grafcet2smv import parse, names  # noqa: E402
from taskio import TASK_IO  # noqa: E402

STAGES = ['schema', 'step count', 'transition count', 'initial steps', 'outputs', 'step correspondence',
          'receptivity', 'forcing', 'timer ownership', 'consistent']


class Model:
    def __init__(self, d, task):
        io = TASK_IO[task]
        self.steps = [x for g in d['graphs'] for x in g['steps']]
        if len(set(self.steps)) != len(self.steps):
            raise ValueError('duplicate step names')
        self.graph_of = {x: g['name'] for g in d['graphs'] for x in g['steps']}
        self.initial = {x for g in d['graphs'] for x in g.get('initial', [])}
        self.trans = []
        derived = {k: parse(v) for k, v in io['derived'].items()}
        allowed = set(io['inputs']) | set(derived) | set(self.steps)
        for t in d['transitions']:
            g = parse(t['guard'])
            bad = names(g) - allowed
            if bad:
                raise ValueError('unknown identifier in guard: %s' % ', '.join(sorted(bad)))
            if not set(t['from']) <= set(self.steps) or not set(t['to']) <= set(self.steps):
                raise ValueError('transition %s refers to an unknown step' % t.get('id'))
            self.trans.append((frozenset(t['from']), frozenset(t['to']), expand(g, derived)))
        self.outputs = {}
        for k in io['outputs']:
            if k not in d.get('outputs', {}):
                raise ValueError('output %s missing' % k)
            e = parse(d['outputs'][k])
            if names(e) - set(self.steps):
                raise ValueError('output %s refers to an unknown identifier' % k)
            self.outputs[k] = e
        self.forcing = [(f['by'], f['graph'], frozenset(f['situation'])) for f in d.get('forcing', [])]
        self.owned = {k: (v['step'], bool(v['neutral']), norm_preset(v.get('preset')))
                      for k, v in d.get('owned', {}).items()}
        self.domains = {k: (v if isinstance(v, list) else [False, True]) for k, v in io['inputs'].items()}

    def signature(self, x):
        alone = tuple(sorted(k for k, e in self.outputs.items() if evaluate(e, {y: (y == x) for y in self.steps})))
        owns = tuple(sorted((k, n, p or '') for k, (s, n, p) in self.owned.items() if s == x))
        return (x in self.initial, sum(x in f for f, _, _ in self.trans), sum(x in t for _, t, _ in self.trans),
                alone, owns, any(b == x for b, _, _ in self.forcing))


def norm_preset(p):
    """Timer presets are compared by value: parameter names case-insensitively, durations without spaces."""
    return None if p is None else str(p).replace(' ', '').lower()


def expand(node, derived):
    op = node[0]
    if op == 'var' and node[1] in derived:
        return derived[node[1]]
    if op in ('const', 'var', 'eq'):
        return node
    return (op,) + tuple(expand(x, derived) if isinstance(x, tuple) else x for x in node[1:])


def rename(node, m):
    op = node[0]
    if op == 'var':
        return ('var', m.get(node[1], node[1]))
    if op in ('const', 'eq'):
        return node
    return (op,) + tuple(rename(x, m) if isinstance(x, tuple) else x for x in node[1:])


def evaluate(node, env):
    op = node[0]
    if op == 'const':
        return node[1]
    if op == 'var':
        return env[node[1]]
    if op == 'eq':
        return env[node[1]] == node[2]
    if op == 'not':
        return not evaluate(node[1], env)
    if op == 'and':
        return evaluate(node[1], env) and evaluate(node[2], env)
    if op == 'or':
        return evaluate(node[1], env) or evaluate(node[2], env)
    if op == 'imp':
        return (not evaluate(node[1], env)) or evaluate(node[2], env)
    if op == 'iff':
        return evaluate(node[1], env) == evaluate(node[2], env)
    raise ValueError(op)


def equivalent(a, b, domains):
    vs = sorted(names(a) | names(b))
    if len(vs) > 18:
        raise ValueError('too many variables for an exhaustive comparison: %d' % len(vs))
    doms = [domains.get(v, [False, True]) for v in vs]
    for combo in itertools.product(*doms):
        env = dict(zip(vs, combo))
        if evaluate(a, env) != evaluate(b, env):
            return False
    return True


def compare(task, d1, d2):
    """Returns (consistent, discrepancy class)."""
    try:
        a, b = Model(d1, task), Model(d2, task)
    except (ValueError, KeyError, SyntaxError, TypeError) as e:
        return False, 'schema: %s' % e
    if len(a.steps) != len(b.steps):
        return False, 'step count (%d vs %d)' % (len(a.steps), len(b.steps))
    if len(a.trans) != len(b.trans):
        return False, 'transition count (%d vs %d)' % (len(a.trans), len(b.trans))
    if len(a.initial) != len(b.initial):
        return False, 'initial steps'
    best = [0]

    def note(stage):
        best[0] = max(best[0], STAGES.index(stage))

    sig_a = {x: a.signature(x) for x in a.steps}
    sig_b = {y: b.signature(y) for y in b.steps}
    if sorted(map(repr, sig_a.values())) != sorted(map(repr, sig_b.values())):
        note('outputs')
        return False, 'step correspondence (no matching step profiles: initial step, degrees, actions, timers)'
    order = sorted(a.steps, key=lambda x: sum(1 for y in b.steps if sig_b[y] == sig_a[x]))
    result = [None]

    def check(m):
        gm = {}
        for x, y in m.items():
            if gm.setdefault(a.graph_of[x], b.graph_of[y]) != b.graph_of[y]:
                note('step correspondence')
                return False
        if len(set(gm.values())) != len(gm) or len(gm) != len(set(b.graph_of.values())):
            note('step correspondence')
            return False
        # transitions: structure first, then receptivities within each structure group
        groups_a, groups_b = {}, {}
        for f, t, g in a.trans:
            groups_a.setdefault((frozenset(m[s] for s in f), frozenset(m[s] for s in t)), []).append(rename(g, m))
        for f, t, g in b.trans:
            groups_b.setdefault((f, t), []).append(g)
        if {k: len(v) for k, v in groups_a.items()} != {k: len(v) for k, v in groups_b.items()}:
            note('step correspondence')
            return False
        note('receptivity')
        for k, ga in groups_a.items():
            gb = groups_b[k]
            if not any(all(equivalent(x, y, a.domains) for x, y in zip(ga, perm))
                       for perm in itertools.permutations(gb)):
                return False
        note('forcing')
        fa = {(m[bstep], gm.get(g, g), frozenset(m[s] for s in sit)) for bstep, g, sit in a.forcing}
        if fa != set(b.forcing):
            return False
        note('timer ownership')
        if {k: (m[s], n, p) for k, (s, n, p) in a.owned.items()} != b.owned:
            return False
        for k in a.outputs:
            if not equivalent(rename(a.outputs[k], m), b.outputs[k], {}):
                return False
        note('consistent')
        return True

    def search(i, m, used):
        if result[0]:
            return
        if i == len(order):
            if check(m):
                result[0] = dict(m)
            return
        x = order[i]
        for y in b.steps:
            if y not in used and sig_b[y] == sig_a[x]:
                if a.graph_of[x] in {a.graph_of[k] for k in m} and \
                        any(a.graph_of[k] == a.graph_of[x] and b.graph_of[v] != b.graph_of[y] for k, v in m.items()):
                    continue
                m[x] = y
                used.add(y)
                search(i + 1, m, used)
                used.discard(y)
                del m[x]

    search(0, {}, set())
    if result[0]:
        return True, ''
    stage = STAGES[best[0]]
    return False, {'receptivity': 'receptivity (no correspondence with equivalent receptivities)',
                   'forcing': 'forcing order', 'timer ownership': 'timer ownership or actions',
                   'step correspondence': 'step correspondence (structure)',
                   'outputs': 'actions'}.get(stage, stage)


def selftest():
    ref = json.load(open(os.path.join(HERE, '..', 'nusmv', 'tank_reference.json'), encoding='utf-8'))
    t2 = {'graphs': [{'name': 'G1', 'steps': ['x0', 'x1', 'x2'], 'initial': ['x0']},
                     {'name': 'G0', 'steps': ['x10', 'x11'], 'initial': ['x10']}],
          'transitions': [{'id': 'a', 'from': ['x0'], 'to': ['x1'], 'guard': 'start'},
                          {'id': 'b', 'from': ['x1'], 'to': ['x2'], 'guard': 'timer_done | LSHH'},
                          {'id': 'c', 'from': ['x2'], 'to': ['x0'], 'guard': 'TRUE'},
                          {'id': 'd', 'from': ['x10'], 'to': ['x11'], 'guard': 'stop'},
                          {'id': 'e', 'from': ['x11'], 'to': ['x10'], 'guard': '!stop'}],
          'outputs': {'fill_valve': 'x1', 'discharge_valve': 'FALSE'},
          'forcing': [{'by': 'x11', 'graph': 'G1', 'situation': ['x0']}],
          'owned': {'timer_done': {'step': 'x1', 'neutral': False, 'preset': 'TimerDuration'}}}
    ren = json.loads(json.dumps(t2).replace('"x1"', '"xA"').replace('"x2"', '"xB"').replace('x1 ', 'xA ')
                     .replace('"x10"', '"xS0"').replace('"x11"', '"xS1"'))
    ren['outputs']['fill_valve'] = 'xA'
    ren['transitions'][1]['guard'] = 'LSHH | timer_done'
    cases = [('renamed steps, reordered guard', t2, ren, True),
             ('LSHH written as r = HIGH', t2, dict(t2, transitions=[dict(t, guard='timer_done | r = HIGH')
                                                                     if t['id'] == 'b' else t
                                                                     for t in t2['transitions']]), True),
             ('overfill term deleted', t2, dict(t2, transitions=[dict(t, guard='timer_done') if t['id'] == 'b'
                                                                 else t for t in t2['transitions']]), False),
             ('stop by transitions instead of forcing', t2,
              {'graphs': [{'name': 'G1', 'steps': ['x0', 'x1', 'x2'], 'initial': ['x0']}],
               'transitions': [{'id': 'a', 'from': ['x0'], 'to': ['x1'], 'guard': 'start & !stop'},
                               {'id': 'b', 'from': ['x1'], 'to': ['x2'], 'guard': 'timer_done | LSHH | stop'},
                               {'id': 'c', 'from': ['x2'], 'to': ['x0'], 'guard': 'TRUE'}],
               'outputs': {'fill_valve': 'x1', 'discharge_valve': 'FALSE'},
               'owned': {'timer_done': {'step': 'x1', 'neutral': False, 'preset': 'TimerDuration'}}}, False),
             ('timer preset differs', t2, dict(t2, owned={'timer_done': {'step': 'x1', 'neutral': False,
                                                                         'preset': 'T#5s'}}), False),
             ('unknown identifier', t2, dict(t2, transitions=[dict(t, guard='level_high') if t['id'] == 'b' else t
                                                              for t in t2['transitions']]), False)]
    ok = True
    for name, x, y, want in cases:
        got, why = compare('T2', x, y)
        ok &= (got == want)
        print('  %-40s consistent=%s %s %s' % (name, got, '(' + why + ')' if why else '', 'ok' if got == want else 'WRONG'))
    t4 = {'graphs': [{'name': 'G1', 'steps': ['x0', 'x1', 'x2'], 'initial': ['x0']},
                     {'name': 'G0', 'steps': ['x10', 'x11'], 'initial': ['x10']}],
          'transitions': [{'id': 'a', 'from': ['x0'], 'to': ['x1'], 'guard': 'start'},
                          {'id': 'b', 'from': ['x1'], 'to': ['x2'], 'guard': 'settled | r = HIGH'},
                          {'id': 'c', 'from': ['x2'], 'to': ['x0'], 'guard': 'TRUE'},
                          {'id': 'd', 'from': ['x10'], 'to': ['x11'], 'guard': 'stop'},
                          {'id': 'e', 'from': ['x11'], 'to': ['x10'], 'guard': '!stop'}],
          'outputs': {'fill_valve': 'x1', 'discharge_valve': 'x1'},
          'forcing': [{'by': 'x11', 'graph': 'G1', 'situation': ['x0']}],
          'owned': {'settled': {'step': 'x1', 'neutral': False, 'preset': 't_h'}}}
    t4b = json.loads(json.dumps(t4))
    t4b['graphs'][1]['name'] = 'GS'
    t4b['forcing'][0]['graph'] = 'G1'
    t4b['transitions'][1]['guard'] = '!(r = LOW | r = MID) | settled'
    got, why = compare('T4', t4, t4b)
    print('  %-40s consistent=%s %s' % ('T4: renamed graph, rewritten receptivity', got, 'ok' if got else 'WRONG ' + why))
    ok &= got
    t4c = json.loads(json.dumps(t4))
    t4c['outputs']['discharge_valve'] = 'FALSE'
    got, why = compare('T4', t4, t4c)
    print('  %-40s consistent=%s (%s) %s' % ('T4: discharge valve never opened', got, why, 'ok' if not got else 'WRONG'))
    ok &= not got
    print('SELFTEST %s' % ('passed' if ok else 'FAILED'))
    return ok


def main():
    if sys.argv[1:] == ['--selftest']:
        sys.exit(0 if selftest() else 1)
    task, p1, p2 = sys.argv[1:4]
    ok, why = compare(task, json.load(open(p1, encoding='utf-8')), json.load(open(p2, encoding='utf-8')))
    print('consistent' if ok else 'discrepancy: ' + why)


if __name__ == '__main__':
    main()
