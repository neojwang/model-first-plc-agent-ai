#!/usr/bin/env python3
"""GRAFCET tuple (JSON) -> NuSMV model, plus an explicit-state CTL pre-check.  Version 2.

Usage:
  python3 grafcet2smv.py MODEL.json --smv OUT.smv      # write the NuSMV model
  python3 grafcet2smv.py MODEL.json --check            # explicit-state check of the specs
  python3 grafcet2smv.py MODEL.json --mutants          # seeded faults: are the specs sensitive?
  python3 grafcet2smv.py MODEL.json --selfcheck OUT.smv
        # evaluates the DEFINE/next() equations of OUT.smv in Python and compares the resulting
        # transition relation with the explicit-state model on every reachable state

The JSON holds the elements of Equation (1): steps S, transitions T with receptivities, actions
(outputs), the initial situation X_init, and the forcing order of the stop-handling GRAFCET G0.

Semantics (one model step = one evolution to a stable situation; Mross et al., ETFA 2023, [22]):
  * micro-step: all enabled transitions whose receptivity is true fire simultaneously; a step that is
    deactivated and activated in the same micro-step stays active; the forcing order of a forcing
    step that is active after the micro-step is applied in the same micro-step (preemption).
  * search for stability: the inputs are not re-read during a transient run [22, Sec. IV]; input
    events ("events") are valid only in the first micro-step [22, Sec. III B]; evolutions require no
    time [22, Sec. III G], so a time or completion condition owned by a step ("owned": timer output,
    t/a, Data logged) takes its neutral value unless the owning step has been active without
    interruption since the start of the evolution.
  * outputs (continuous actions) are evaluated on the stable situation only [22, Sec. IV].
  * K = |S| + 1 micro-steps are computed; "stable" is true when one more micro-step changes
    nothing.  A run that does not reach a stable situation within K micro-steps violates W5;
    never-ending transient cycles should be detected by verification [22, Sec. III G].

The explicit-state checker is a pre-check written for this study.  It is NOT NuSMV; the results to be
reported come from running NuSMV on the generated .smv file.
"""
import copy
import itertools
import json
import re
import sys

# ------------------------------------------------------------------ expression parser (SMV subset + CTL)
TOKEN = re.compile(r'\s*(<->|->|!|&|\||\(|\)|\[|\]|=|[A-Za-z_][A-Za-z0-9_]*)')
TEMPORAL = {'AG', 'AX', 'AF', 'EG', 'EX', 'EF'}


def tokenize(s):
    pos, out = 0, []
    s = s.strip()
    while pos < len(s):
        m = TOKEN.match(s, pos)
        if not m:
            raise SyntaxError('bad token at %r' % s[pos:])
        out.append(m.group(1))
        pos = m.end()
    return out


class Parser:
    def __init__(self, s):
        self.t, self.k = tokenize(s), 0

    def peek(self):
        return self.t[self.k] if self.k < len(self.t) else None

    def eat(self, tok=None):
        cur = self.peek()
        if tok is not None and cur != tok:
            raise SyntaxError('expected %s, got %s' % (tok, cur))
        self.k += 1
        return cur

    def parse(self):
        e = self.imp()
        if self.peek() is not None:
            raise SyntaxError('trailing tokens: %s' % self.t[self.k:])
        return e

    def imp(self):
        a = self.iff()
        if self.peek() == '->':
            self.eat()
            return ('imp', a, self.imp())
        return a

    def iff(self):
        a = self.orr()
        while self.peek() == '<->':
            self.eat()
            a = ('iff', a, self.orr())
        return a

    def orr(self):
        a = self.andd()
        while self.peek() == '|':
            self.eat()
            a = ('or', a, self.andd())
        return a

    def andd(self):
        a = self.unary()
        while self.peek() == '&':
            self.eat()
            a = ('and', a, self.unary())
        return a

    def unary(self):
        p = self.peek()
        if p == '!':
            self.eat()
            return ('not', self.unary())
        if p in TEMPORAL:
            self.eat()
            return (p, self.unary())
        if p in ('E', 'A') and self.k + 1 < len(self.t) and self.t[self.k + 1] == '[':
            q = self.eat()
            self.eat('[')
            a = self.imp()
            self.eat('U')
            b = self.imp()
            self.eat(']')
            return (q + 'U', a, b)
        return self.atom()

    def atom(self):
        p = self.eat()
        if p == '(':
            e = self.imp()
            self.eat(')')
            return e
        if p == 'TRUE':
            return ('const', True)
        if p == 'FALSE':
            return ('const', False)
        if p is None or not re.match(r'[A-Za-z_]', p):
            raise SyntaxError('unexpected %s' % p)
        if self.peek() == '=':
            self.eat()
            return ('eq', p, self.eat())
        return ('var', p)


def parse(s):
    return Parser(s).parse()


def names(node, out=None):
    out = set() if out is None else out
    if node[0] in ('var', 'eq'):
        out.add(node[1])
    for x in node[1:]:
        if isinstance(x, tuple):
            names(x, out)
    return out


# ------------------------------------------------------------------ model
class Model:
    def __init__(self, spec):
        self.spec = spec
        self.inputs = list(spec['inputs'].items())
        self.input_names = [n for n, _ in self.inputs]
        self.steps = [x for g in spec['graphs'] for x in g['steps']]
        self.graph_of = {x: g['name'] for g in spec['graphs'] for x in g['steps']}
        self.init = tuple(x in {y for g in spec['graphs'] for y in g['initial']} for x in self.steps)
        self.trans = [(t['id'], t['from'], t['to'], parse(t['guard'])) for t in spec['transitions']]
        self.outputs = {k: parse(v) for k, v in spec['outputs'].items()}
        self.derived = {k: parse(v) for k, v in spec.get('derived', {}).items()}
        self.owned = spec.get('owned', {})
        self.events = list(spec.get('events', []))
        special = set(self.owned) | set(self.events)
        for k, v in self.derived.items():
            assert not (names(v) & special), 'derived input %s may not use owned or event inputs' % k
        for v, o in self.owned.items():
            assert v in self.input_names and o['step'] in self.steps, v
        self.domains = [[False, True] if d == 'boolean' else list(d) for _, d in self.inputs]
        self.combos = list(itertools.product(*self.domains))
        self.full = (1 << len(self.combos)) - 1
        self.idx = {x: k for k, x in enumerate(self.steps)}
        self.K = len(self.steps) + 1

    # -- environment of a state (stable situation + current inputs)
    def env(self, conf, combo, k=None):
        e = {x: conf[j] for j, x in enumerate(self.steps)}
        e.update({name: combo[j] for j, name in enumerate(self.input_names)})
        for d, node in self.derived.items():
            e[d] = self.ev(node, e)
        if k is not None and hasattr(self, 'stab'):
            e['stable'] = self.stab[conf][k]
        return e

    def ev(self, node, e):
        op = node[0]
        if op == 'const':
            return node[1]
        if op == 'var':
            if node[1] in e:
                return e[node[1]]
            if node[1] in self.outputs:
                return self.ev(self.outputs[node[1]], e)
            raise NameError(node[1])
        if op == 'eq':
            return e[node[1]] == node[2]
        if op == 'not':
            return not self.ev(node[1], e)
        if op == 'and':
            return self.ev(node[1], e) and self.ev(node[2], e)
        if op == 'or':
            return self.ev(node[1], e) or self.ev(node[2], e)
        if op == 'imp':
            return (not self.ev(node[1], e)) or self.ev(node[2], e)
        if op == 'iff':
            return self.ev(node[1], e) == self.ev(node[2], e)
        raise ValueError('temporal operator inside a state formula: %s' % op)

    # -- one micro-step of the search for stability
    def micro(self, conf, cont, combo, first):
        e = {x: conf[j] for j, x in enumerate(self.steps)}
        raw = {name: combo[j] for j, name in enumerate(self.input_names)}
        for name in self.input_names:
            if name in self.owned:
                o = self.owned[name]
                e[name] = raw[name] if cont[self.idx[o['step']]] else o['neutral']
            elif name in self.events:
                e[name] = raw[name] if first else False
            else:
                e[name] = raw[name]
        for d, node in self.derived.items():
            e[d] = self.ev(node, e)
        fired = [(f, t) for _, f, t, g in self.trans if all(e[s] for s in f) and self.ev(g, e)]
        nxt = {}
        for x in self.steps:
            leave = any(x in f for f, _ in fired)
            enter = any(x in t for _, t in fired)
            nxt[x] = (e[x] and not leave) or enter
        for fo in self.spec.get('forcing', []):
            if nxt[fo['by']]:
                g = next(g for g in self.spec['graphs'] if g['name'] == fo['graph'])
                for x in g['steps']:
                    nxt[x] = x in fo['situation']
        c2 = tuple(nxt[x] for x in self.steps)
        cont2 = tuple(a and b for a, b in zip(cont, c2))
        return c2, cont2

    def evolve(self, conf, combo):
        c, cont = conf, conf
        for k in range(1, self.K + 1):
            c, cont = self.micro(c, cont, combo, first=(k == 1))
        c_more, _ = self.micro(c, cont, combo, first=False)
        return c, c_more == c

    def explore(self):
        confs, frontier, nxt, stab = {self.init}, [self.init], {}, {}
        while frontier:
            c = frontier.pop()
            row, srow = [], []
            for combo in self.combos:
                c2, ok = self.evolve(c, combo)
                row.append(c2)
                srow.append(ok)
                if c2 not in confs:
                    confs.add(c2)
                    frontier.append(c2)
            nxt[c], stab[c] = row, srow
        self.confs, self.nxt, self.stab = sorted(confs), nxt, stab
        return self

    # sets of states are dicts conf -> bitmask over input combos
    def sat(self, node):
        op = node[0]
        if op in ('const', 'var', 'eq', 'not', 'and', 'or', 'imp', 'iff') and not self.has_temporal(node):
            out = {}
            for c in self.confs:
                m = 0
                for k, combo in enumerate(self.combos):
                    if self.ev(node, self.env(c, combo, k)):
                        m |= 1 << k
                out[c] = m
            return out
        if op == 'not':
            a = self.sat(node[1])
            return {c: self.full & ~a[c] for c in self.confs}
        if op in ('and', 'or', 'imp', 'iff'):
            a, b = self.sat(node[1]), self.sat(node[2])
            f = {'and': lambda x, y: x & y, 'or': lambda x, y: x | y,
                 'imp': lambda x, y: (self.full & ~x) | y,
                 'iff': lambda x, y: self.full & ~(x ^ y)}[op]
            return {c: f(a[c], b[c]) for c in self.confs}
        if op == 'EX':
            return self.ex(self.sat(node[1]))
        if op == 'AX':
            return self.ax(self.sat(node[1]))
        if op == 'EF':
            return self.lfp(lambda z, p=self.sat(node[1]): {c: p[c] | self.ex(z)[c] for c in self.confs})
        if op == 'AF':
            return self.lfp(lambda z, p=self.sat(node[1]): {c: p[c] | self.ax(z)[c] for c in self.confs})
        if op == 'AG':
            return self.gfp(lambda z, p=self.sat(node[1]): {c: p[c] & self.ax(z)[c] for c in self.confs})
        if op == 'EG':
            return self.gfp(lambda z, p=self.sat(node[1]): {c: p[c] & self.ex(z)[c] for c in self.confs})
        if op == 'EU':
            a, b = self.sat(node[1]), self.sat(node[2])
            return self.lfp(lambda z: {c: b[c] | (a[c] & self.ex(z)[c]) for c in self.confs})
        if op == 'AU':
            a, b = self.sat(node[1]), self.sat(node[2])
            return self.lfp(lambda z: {c: b[c] | (a[c] & self.ax(z)[c]) for c in self.confs})
        raise ValueError(op)

    def has_temporal(self, node):
        if node[0] in TEMPORAL or node[0] in ('EU', 'AU'):
            return True
        return any(isinstance(x, tuple) and self.has_temporal(x) for x in node[1:])

    def ex(self, z):
        return {c: sum(1 << k for k, c2 in enumerate(self.nxt[c]) if z[c2]) for c in self.confs}

    def ax(self, z):
        return {c: sum(1 << k for k, c2 in enumerate(self.nxt[c]) if z[c2] == self.full) for c in self.confs}

    def lfp(self, f):
        z = {c: 0 for c in self.confs}
        while True:
            z2 = f(z)
            if z2 == z:
                return z
            z = z2

    def gfp(self, f):
        z = {c: self.full for c in self.confs}
        while True:
            z2 = f(z)
            if z2 == z:
                return z
            z = z2

    def holds(self, ctl):
        return self.sat(parse(ctl))[self.init] == self.full

    def counterexample(self, ctl):
        """A reachable state (situation, inputs) at which the body of an AG formula fails."""
        node = parse(ctl)
        if node[0] != 'AG':
            return None
        body = self.sat(node[1])
        for c in self.confs:
            if body[c] != self.full:
                k = next(k for k in range(len(self.combos)) if not (body[c] >> k) & 1)
                return self.active(c), dict(zip(self.input_names, self.combos[k]))
        return None

    def active(self, c):
        return '{' + ', '.join(x for k, x in enumerate(self.steps) if c[k]) + '}'


# ------------------------------------------------------------------ NuSMV generator
def smv_expr(node, ren=None):
    ren = ren or {}
    op = node[0]
    if op == 'const':
        return 'TRUE' if node[1] else 'FALSE'
    if op == 'var':
        return ren.get(node[1], node[1])
    if op == 'eq':
        return '%s = %s' % (ren.get(node[1], node[1]), node[2])
    if op == 'not':
        return '!(%s)' % smv_expr(node[1], ren)
    sym = {'and': '&', 'or': '|', 'imp': '->', 'iff': '<->'}[op]
    return '(%s %s %s)' % (smv_expr(node[1], ren), sym, smv_expr(node[2], ren))


def to_smv(spec):
    m = Model(spec)
    K = m.K
    L = ['-- generated by grafcet2smv.py (version 2) from %s' % spec['name'],
         '-- source: %s' % spec.get('source', ''),
         '-- one model step = one evolution to a stable situation (search for stability, %d micro-steps);' % K,
         '-- see the docstring of grafcet2smv.py for the semantics',
         'MODULE main', 'VAR']
    for name, d in m.inputs:
        kind = 'event' if name in m.events else ('owned by %s' % m.owned[name]['step'] if name in m.owned else 'level')
        L.append('  %s : %s;  -- input (unconstrained, %s)' % (name, 'boolean' if d == 'boolean' else '{%s}' % ', '.join(d), kind))
    for x in m.steps:
        L.append('  %s : boolean;  -- step of %s (stable situation)' % (x, m.graph_of[x]))
    L.append('DEFINE')
    for d, node in m.derived.items():
        L.append('  %s := %s;' % (d, smv_expr(node)))
    forced = {}
    for fo in spec.get('forcing', []):
        g = next(g for g in spec['graphs'] if g['name'] == fo['graph'])
        for x in g['steps']:
            forced[x] = (fo['by'], x in fo['situation'])

    def sv(k, x):
        return x if k == 0 else 's%d_%s' % (k, x)

    def cv(k, x):
        return x if k == 0 else 'c%d_%s' % (k, x)

    for k in range(1, K + 2):
        L.append('  -- micro-step %d%s' % (k, ' (events valid)' if k == 1 else ''))
        ren = {x: sv(k - 1, x) for x in m.steps}
        for name in m.input_names:
            if name in m.owned:
                o = m.owned[name]
                own = cv(k - 1, o['step'])
                expr = ('(%s & %s)' % (own, name)) if not o['neutral'] else ('(!%s | %s)' % (own, name))
                L.append('  i%d_%s := %s;' % (k, name, expr))
                ren[name] = 'i%d_%s' % (k, name)
            elif name in m.events:
                L.append('  i%d_%s := %s;' % (k, name, name if k == 1 else 'FALSE'))
                ren[name] = 'i%d_%s' % (k, name)
        for tid, f, t, g in m.trans:
            L.append('  f%d_%s := %s & %s;' % (k, tid, ' & '.join(sv(k - 1, s) for s in f), smv_expr(g, ren)))
        for x in m.steps:
            lv = ' | '.join('f%d_%s' % (k, tid) for tid, f, _, _ in m.trans if x in f) or 'FALSE'
            en = ' | '.join('f%d_%s' % (k, tid) for tid, _, t, _ in m.trans if x in t) or 'FALSE'
            L.append('  n%d_%s := (%s & !(%s)) | (%s);' % (k, x, sv(k - 1, x), lv, en))
        for x in m.steps:
            if x in forced:
                by, val = forced[x]
                L.append('  %s := (n%d_%s & %s) | (!n%d_%s & n%d_%s);' % (
                    sv(k, x), k, by, 'TRUE' if val else 'FALSE', k, by, k, x))
            else:
                L.append('  %s := n%d_%s;' % (sv(k, x), k, x))
        for x in m.steps:
            L.append('  %s := %s & %s;' % (cv(k, x), cv(k - 1, x), sv(k, x)))
    L.append('  stable := %s;' % ' & '.join('(%s <-> %s)' % (sv(K + 1, x), sv(K, x)) for x in m.steps))
    for k, v in spec['outputs'].items():
        L.append('  %s := %s;' % (k, smv_expr(parse(v))))
    L.append('ASSIGN')
    for k, x in enumerate(m.steps):
        L.append('  init(%s) := %s;' % (x, 'TRUE' if m.init[k] else 'FALSE'))
    for x in m.steps:
        L.append('  next(%s) := %s;' % (x, sv(K, x)))
    for s in spec['specs']:
        L.append('-- %s: %s' % (s['id'], s.get('what', '')))
        L.append('SPEC %s' % s['ctl'])
    return '\n'.join(L) + '\n'


# ------------------------------------------------------------------ self-check of the generated SMV
def py_expr(node):
    op = node[0]
    if op == 'const':
        return 'True' if node[1] else 'False'
    if op == 'var':
        return 'V[%r]' % node[1]
    if op == 'eq':
        return '(V[%r] == %r)' % (node[1], node[2])
    if op == 'not':
        return '(not %s)' % py_expr(node[1])
    if op == 'and':
        return '(%s and %s)' % (py_expr(node[1]), py_expr(node[2]))
    if op == 'or':
        return '(%s or %s)' % (py_expr(node[1]), py_expr(node[2]))
    if op == 'imp':
        return '((not %s) or %s)' % (py_expr(node[1]), py_expr(node[2]))
    if op == 'iff':
        return '(%s == %s)' % (py_expr(node[1]), py_expr(node[2]))
    raise ValueError(op)


def selfcheck(spec, smv_path):
    """Evaluate the DEFINE and next() equations of the generated .smv file and compare the resulting
    successor situation and stability flag with the explicit-state model on every reachable state."""
    text = open(smv_path, encoding='utf-8').read()
    body = text.split('DEFINE', 1)[1].split('ASSIGN', 1)
    defs = re.findall(r'^\s*([A-Za-z_][A-Za-z0-9_]*)\s*:=\s*(.+?);\s*$', body[0], re.M)
    nexts = dict(re.findall(r'^\s*next\(([A-Za-z0-9_]+)\)\s*:=\s*([A-Za-z0-9_]+);', body[1], re.M))
    src = ['def run(V):']
    for name, e in defs:
        src.append('    V[%r] = %s' % (name, py_expr(parse(e))))
    src.append('    return V')
    ns = {}
    exec('\n'.join(src), ns)
    m = Model(spec).explore()
    checked = mism = 0
    for c in m.confs:
        for k, combo in enumerate(m.combos):
            V = {x: c[j] for j, x in enumerate(m.steps)}
            V.update({n: combo[j] for j, n in enumerate(m.input_names)})
            V = ns['run'](V)
            c2 = tuple(V[nexts[x]] for x in m.steps)
            checked += 1
            if c2 != m.nxt[c][k] or V['stable'] != m.stab[c][k]:
                mism += 1
    return checked, mism, len(defs)


# ------------------------------------------------------------------ seeded faults
MUTANTS = [
    ('Ma', 'E1 loses the overfill term LSHH (Table 3)', {'tE1_S1': 'timer_q'}),
    ('Mb', 'step 21 can no longer reach S2 (Table 4)', {'t21_S2': 'FALSE'}),
    ('Mc', 'G0 forcing order removed', 'no-forcing'),
    ('Md', 'E3 loses the overfill term h >= h_max (Table 5)', {'tE3_S3': 'hold_ok'}),
    ('Me', 'End of M2 never fires (S2 is a dead end)', {'tEndM2': 'FALSE'}),
    ('Mf', 'pause step 22 never resumes filling', {'t22_21': 'FALSE'}),
    ('Mg', 'E3 is never left', {'tE3_S3': 'FALSE'}),
    ('Mh', 'steps 21 and 22 ignore the timers (transient cycle)', {'t21_22': '!LSH', 't22_21': 'TRUE'}),
]


def mutate(spec, patch):
    s = copy.deepcopy(spec)
    if patch == 'no-forcing':
        s['forcing'] = []
    else:
        for t in s['transitions']:
            if t['id'] in patch:
                t['guard'] = patch[t['id']]
    return s


def check(spec, out=sys.stdout, extra=()):
    m = Model(spec).explore()
    print('model %s: %d reachable stable situations x %d input combinations = %d states' % (
        spec['name'], len(m.confs), len(m.combos), len(m.confs) * len(m.combos)), file=out)
    res = {}
    for s in list(spec['specs']) + list(extra):
        ok = m.holds(s['ctl'])
        res[s['id']] = ok
        print('  %-6s %-5s %s' % (s['id'], 'holds' if ok else 'FAILS', s['ctl']), file=out)
        if not ok:
            cx = m.counterexample(s['ctl'])
            if cx:
                print('         counterexample state: situation %s, inputs %s' % cx, file=out)
    return res


def main():
    spec = json.load(open(sys.argv[1], encoding='utf-8'))
    args = sys.argv[2:]
    if '--smv' in args:
        path = args[args.index('--smv') + 1]
        open(path, 'w', encoding='utf-8').write(to_smv(spec))
        print('wrote', path)
    if '--selfcheck' in args:
        path = args[args.index('--selfcheck') + 1]
        n, bad, nd = selfcheck(spec, path)
        print('self-check of %s: %d DEFINE equations evaluated on %d reachable states; mismatches with the '
              'explicit-state model: %d' % (path, nd, n, bad))
    if '--check' in args:
        extra = spec.get('not_used', []) if '--with-rejected' in args else []
        res = check(spec, extra=extra)
        main_ids = [s['id'] for s in spec['specs']]
        print('reference model: %s' % ('all specs hold' if all(res[k] for k in main_ids) else 'SOME SPECS FAIL'))
    if '--mutants' in args:
        base = check(spec, out=open('/dev/null', 'w'))
        print('seeded faults (a mutant is detected when at least one spec that holds on the reference fails):')
        for mid, desc, patch in MUTANTS:
            r = check(mutate(spec, patch), out=open('/dev/null', 'w'))
            killed = [k for k in r if base[k] and not r[k]]
            print('  %s %-52s detected by: %s' % (mid, desc, ', '.join(killed) if killed else 'NOT DETECTED'))


if __name__ == '__main__':
    main()
