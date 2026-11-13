#!/usr/bin/env python3
"""GRAFCET description (JSON) -> equivalent GVM programs in Python, C++, and IEC 61131-3 Structured Text (ST).

The GRAFCET tuple of the paper (Equation (1); schema in exec/prompts/templates/_schema.md, with the extensions used
in nusmv/tank_reference.json: enumerated inputs, derived inputs, events) is used as the description language of a
GRAFCET virtual machine (GVM).  Each generated program executes one evolution to a stable situation per tick (one
Python call, one C++ call, one PLC scan) with the semantics of nusmv/grafcet2smv.py, which is the semantics checked
with NuSMV (Mross et al., ETFA 2023):
  * micro-step: all enabled transitions whose receptivity is true fire simultaneously; a step that is deactivated
    and activated in the same micro-step stays active; forcing orders are applied in the same micro-step;
  * the inputs are not re-read during a transient run; events are valid in the first micro-step only; a condition
    owned by a step takes its neutral value unless the owning step has been active since the start of the
    evolution;
  * K = |S| + 1 micro-steps are computed; the situation is stable when one more micro-step changes nothing;
  * outputs are evaluated on the resulting situation.

  python3 grafcet2gvm.py MODEL.json --out DIR
      writes DIR/<name>_gvm.py, <name>_gvm.hpp, <name>_gvm_main.cpp, <name>_gvm.st and <name>_gvm_io.json

Inputs are given in the order of "inputs" in the JSON: Boolean inputs as 0 or 1, enumerated inputs as the index of
their value in the JSON list (for nusmv/tank_reference.json: mode timer 0, tontof 1, pid 2; r LOW 0, MID 1, HIGH 2).
The ST program reads them from located inputs and writes the outputs, the stability flag, and the situation to
located outputs (addresses in <name>_gvm_io.json).

--fault is for the negative controls of e3_check.py only: 'event-level' reads events in every micro-step,
'no-forcing' drops the forcing orders.
"""
import argparse
import hashlib
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.dont_write_bytecode = True   # keep the kit folders free of __pycache__
sys.path.insert(0, os.path.join(HERE, '..', 'nusmv'))
import grafcet2smv as g2s  # noqa: E402  (parser and reference semantics)

FAULTS = ('event-level', 'no-forcing')
# fields that define the behavior; the header of every generated program carries their SHA-256, so that a description
# that differs only in documentation fields (for example 'not_used' or 'specs') yields byte-identical programs
SEM_KEYS = ('inputs', 'derived', 'owned', 'events', 'graphs', 'transitions', 'forcing', 'outputs')
SYN = {
    'py': {'not': 'not {}', 'and': '({} and {})', 'or': '({} or {})', 'imp': '((not {}) or {})',
           'iff': '({} == {})', 'eq': '({} == {})', True: 'True', False: 'False'},
    'cpp': {'not': '!{}', 'and': '({} && {})', 'or': '({} || {})', 'imp': '(!{} || {})',
            'iff': '({} == {})', 'eq': '({} == {})', True: 'true', False: 'false'},
    'st': {'not': 'NOT {}', 'and': '({} AND {})', 'or': '({} OR {})', 'imp': '(NOT {} OR {})',
           'iff': '({} = {})', 'eq': '({} = {})', True: 'TRUE', False: 'FALSE'},
}


class Desc:
    """The parsed GRAFCET description (same parser and model as nusmv/grafcet2smv.py)."""

    def __init__(self, spec, fault=None):
        assert fault in (None,) + FAULTS, fault
        m = g2s.Model(spec)
        self.spec, self.fault = spec, fault
        self.name = spec.get('name', 'grafcet')
        self.steps, self.init, self.K = m.steps, m.init, m.K
        self.inputs = m.inputs
        self.enum = {n: list(d) for n, d in self.inputs if d != 'boolean'}
        self.owned, self.events, self.derived = m.owned, m.events, m.derived
        self.trans, self.outputs = m.trans, m.outputs
        self.forcing = [] if fault == 'no-forcing' else list(spec.get('forcing', []))
        self.graph_steps = {g['name']: list(g['steps']) for g in spec['graphs']}
        for n in self.events:
            assert n not in self.enum, 'event %s must be Boolean' % n

    # ---- expressions
    def expr(self, node, lang):
        s, op = SYN[lang], node[0]
        if op == 'const':
            return s[bool(node[1])]
        if op == 'var':
            n = node[1]
            if n in self.steps:
                return n
            if n in self.derived:
                return 'd_' + n
            if n in self.outputs:
                return self.expr(self.outputs[n], lang)
            if n in dict(self.inputs):
                return 'e_' + n
            raise NameError(n)
        if op == 'eq':
            n, v = node[1], node[2]
            assert n in self.enum and v in self.enum[n], (n, v)
            return s['eq'].format('e_' + n, self.enum[n].index(v))
        if op == 'not':
            return s['not'].format(self.expr(node[1], lang))
        if op in ('and', 'or', 'imp', 'iff'):
            return s[op].format(self.expr(node[1], lang), self.expr(node[2], lang))
        raise ValueError('operator %s is not allowed in a receptivity or an action' % op)

    def micro_body(self, lang):
        """Statements of one micro-step, as (kind, target, expression) records rendered per language."""
        st = []
        for n, _ in self.inputs:
            if n in self.owned:
                o = self.owned[n]
                st.append(('cond', 'e_' + n, ('k_' + o['step'], 'in_' + n, SYN[lang][bool(o['neutral'])])))
            elif n in self.events and self.fault != 'event-level':
                st.append(('cond', 'e_' + n, ('first', 'in_' + n, SYN[lang][False])))
            else:
                st.append(('set', 'e_' + n, 'in_' + n))
        for n, node in self.derived.items():
            st.append(('set', 'd_' + n, self.expr(node, lang)))
        for tid, frm, _, guard in self.trans:
            terms = list(frm) + [self.expr(guard, lang)]
            e = terms[0]
            for t in terms[1:]:
                e = SYN[lang]['and'].format(e, t)
            st.append(('set', 'f_' + tid, e))
        for x in self.steps:
            leave = ['f_' + tid for tid, frm, _, _ in self.trans if x in frm]
            enter = ['f_' + tid for tid, _, to, _ in self.trans if x in to]
            e = x
            if leave:
                e = SYN[lang]['and'].format(x, SYN[lang]['not'].format(self.join(leave, 'or', lang)))
            if enter:
                e = SYN[lang]['or'].format(e, self.join(enter, 'or', lang))
            st.append(('set', 'n_' + x, e))
        for fo in self.forcing:
            st.append(('force', 'n_' + fo['by'], [('n_' + s, s in fo['situation'])
                                                    for s in self.graph_steps[fo['graph']]]))
        return st

    def join(self, names, op, lang):
        if len(names) == 1:
            return names[0]
        e = names[0]
        for n in names[1:]:
            e = SYN[lang][op].format(e, n)
        return e

    def io(self):
        """Located variables of the ST program (OpenPLC addressing)."""
        bi = [n for n, d in self.inputs if d == 'boolean']
        wi = [n for n, d in self.inputs if d != 'boolean']
        bo = list(self.outputs) + ['stable']
        loc = {}
        for k, n in enumerate(bi):
            loc['in_' + n] = '%%IX%d.%d' % (100 + k // 8, k % 8)
        for k, n in enumerate(wi):
            loc['in_' + n] = '%%IW%d' % (100 + k)
        for k, n in enumerate(bo):
            loc['out_' + n] = '%%QX%d.%d' % (100 + k // 8, k % 8)
        base = 100 + (len(bo) + 7) // 8
        for k, x in enumerate(self.steps):
            loc['x_' + x] = '%%QX%d.%d' % (base + k // 8, k % 8)
        return {'inputs': [n for n, _ in self.inputs], 'enums': self.enum, 'outputs': list(self.outputs),
                'steps': self.steps, 'init': [bool(b) for b in self.init], 'K': self.K, 'located': loc}


def desc_sha(spec):
    """SHA-256 of the behavioral fields of a description (SEM_KEYS), independent of formatting."""
    sem = {k: spec.get(k) for k in SEM_KEYS}
    return hashlib.sha256(json.dumps(sem, sort_keys=True, ensure_ascii=False).encode('utf-8')).hexdigest()


def header(d, src_sha, comment):
    return [comment + ' Generated by gvm/grafcet2gvm.py from %s.json (description SHA-256 %s); do not edit.' % (d.name, src_sha[:16]),
            comment + ' GVM program: one tick = one evolution of the GRAFCET to a stable situation (semantics of',
            comment + ' nusmv/grafcet2smv.py, checked with NuSMV).' + ('  SEEDED FAULT: %s.' % d.fault if d.fault else '')]


# ------------------------------------------------------------------ Python
def gen_py(d, src_sha):
    L = ['"""' + '\n'.join(x[2:] for x in header(d, src_sha, '#')) + '"""', '']
    L += ['NAME = %r' % d.name, 'STEPS = %r' % (tuple(d.steps),), 'INPUTS = %r' % (tuple(n for n, _ in d.inputs),),
          'ENUMS = %r' % ({n: tuple(v) for n, v in d.enum.items()},), 'OUTPUTS = %r' % (tuple(d.outputs),),
          'INIT = %r' % (tuple(bool(b) for b in d.init),), 'K = %d' % d.K, '', '',
          'def micro(c, k, i, first):',
          '    """One micro-step: the next situation and the continuity of each step since the start of the evolution."""',
          '    (%s,) = c' % ', '.join(d.steps),
          '    (%s,) = k' % ', '.join('k_' + x for x in d.steps)]
    for j, (n, dom) in enumerate(d.inputs):
        L.append('    in_%s = %s' % (n, ('bool(i[%d])' % j) if dom == 'boolean' else ('int(i[%d])' % j)))
    for kind, tgt, e in d.micro_body('py'):
        if kind == 'set':
            L.append('    %s = %s' % (tgt, e))
        elif kind == 'cond':
            L.append('    %s = %s if %s else %s' % (tgt, e[1], e[0], e[2]))
        else:
            L.append('    if %s:' % tgt)
            for v, val in e:
                L.append('        %s = %s' % (v, val))
    L += ['    n = (%s,)' % ', '.join('n_' + x for x in d.steps),
          '    return n, tuple(a and b for a, b in zip(k, n))', '', '',
          'def evolve(c, i):',
          '    """One tick: K micro-steps from situation c with inputs i; returns the situation and the stability flag."""',
          '    k = c',
          '    for m in range(K):',
          '        c, k = micro(c, k, i, m == 0)',
          '    return c, micro(c, k, i, False)[0] == c', '', '',
          'def outputs(c):',
          '    (%s,) = c' % ', '.join(d.steps),
          '    return (%s,)' % ', '.join(d.expr(e, 'py') for e in d.outputs.values()), '', '',
          'class GVM:',
          '    def __init__(self):',
          '        self.c = INIT', '',
          '    def reset(self):',
          '        self.c = INIT', '',
          '    def tick(self, i):',
          '        """Inputs in the order of INPUTS (Boolean 0/1, enumerations by index); returns (situation, stable, outputs)."""',
          '        self.c, stable = evolve(self.c, tuple(i))',
          '        return self.c, stable, outputs(self.c)',
          '',
          '    def active(self):',
          '        return [x for x, a in zip(STEPS, self.c) if a]', '']
    return '\n'.join(L)


# ------------------------------------------------------------------ C++
def gen_hpp(d, src_sha):
    ns = 'gvm_' + d.name
    n_s, n_i, n_o = len(d.steps), len(d.inputs), len(d.outputs)
    q = lambda xs: ', '.join('"%s"' % x for x in xs)
    L = header(d, src_sha, '//') + ['// Inputs in the order of INPUT_NAMES: Boolean 0/1, enumerations by index.', '#pragma once',
                                    '#include <array>', '', 'namespace %s {' % ns,
                                    'constexpr int N_STEPS = %d, N_INPUTS = %d, N_OUTPUTS = %d, K = %d;' % (n_s, n_i, n_o, d.K),
                                    'using Situation = std::array<bool, N_STEPS>;',
                                    'using Inputs = std::array<int, N_INPUTS>;',
                                    'using Outputs = std::array<bool, N_OUTPUTS>;',
                                    'static const char *const STEP_NAMES[N_STEPS] = {%s};' % q(d.steps),
                                    'static const char *const INPUT_NAMES[N_INPUTS] = {%s};' % q([n for n, _ in d.inputs]),
                                    'static const char *const OUTPUT_NAMES[N_OUTPUTS] = {%s};' % q(d.outputs),
                                    'static const Situation INIT = {{%s}};' % ', '.join('true' if b else 'false' for b in d.init),
                                    '',
                                    '// One micro-step: next situation c and continuity k of each step since the start of the evolution.',
                                    'inline void micro(Situation &c, Situation &k, const Inputs &i, bool first) {']
    L.append('  [[maybe_unused]] const bool %s;' % ', '.join('%s = c[%d]' % (x, j) for j, x in enumerate(d.steps)))
    L.append('  [[maybe_unused]] const bool %s;' % ', '.join('k_%s = k[%d]' % (x, j) for j, x in enumerate(d.steps)))
    for j, (n, dom) in enumerate(d.inputs):
        L.append('  const %s in_%s = %s;' % (('bool', n, 'i[%d] != 0' % j) if dom == 'boolean' else ('int', n, 'i[%d]' % j)))
    for kind, tgt, e in d.micro_body('cpp'):
        typ = 'int' if tgt[2:] in d.enum and tgt.startswith('e_') else 'bool'
        if kind == 'set':
            L.append('  %s %s = %s;' % (('const ' + typ) if not tgt.startswith('n_') else typ, tgt, e))
        elif kind == 'cond':
            L.append('  const %s %s = %s ? %s : %s;' % (typ, tgt, e[0], e[1], e[2]))
        else:
            L.append('  if (%s) {' % tgt)
            for v, val in e:
                L.append('    %s = %s;' % (v, 'true' if val else 'false'))
            L.append('  }')
    L += ['  const Situation n = {{%s}};' % ', '.join('n_' + x for x in d.steps),
          '  for (int s = 0; s < N_STEPS; ++s) k[s] = k[s] && n[s];',
          '  c = n;',
          '}', '',
          '// One tick: K micro-steps; returns true when the resulting situation is stable.',
          'inline bool evolve(Situation &c, const Inputs &i) {',
          '  Situation k = c;',
          '  for (int m = 1; m <= K; ++m) micro(c, k, i, m == 1);',
          '  Situation c2 = c, k2 = k;',
          '  micro(c2, k2, i, false);',
          '  return c2 == c;',
          '}', '',
          'inline Outputs outputs(const Situation &c) {',
          '  [[maybe_unused]] const bool %s;' % ', '.join('%s = c[%d]' % (x, j) for j, x in enumerate(d.steps)),
          '  return {{%s}};' % ', '.join(d.expr(e, 'cpp') for e in d.outputs.values()),
          '}', '',
          'struct GVM {',
          '  Situation c = INIT;',
          '  void reset() { c = INIT; }',
          '  bool tick(const Inputs &i) { return evolve(c, i); }',
          '};',
          '}  // namespace %s' % ns, '']
    return '\n'.join(L)


def gen_main(d, src_sha):
    ns = 'gvm_' + d.name
    return '\n'.join(header(d, src_sha, '//') + [
        '// Driver: one command per line on standard input.  "R" resets to the initial situation; "T v1 ... vN" runs one',
        '// tick with the N inputs and prints the situation bits (step order of STEP_NAMES), the stability flag, and the',
        '// output bits (order of OUTPUT_NAMES).',
        '#include <iostream>', '#include <sstream>', '#include <string>', '#include "%s_gvm.hpp"' % d.name, '',
        'int main() {',
        '  %s::GVM g;' % ns,
        '  std::string line;',
        '  while (std::getline(std::cin, line)) {',
        '    std::istringstream s(line);',
        '    std::string op;',
        '    s >> op;',
        '    if (op == "R") { g.reset(); continue; }',
        '    if (op != "T") continue;',
        '    %s::Inputs in{};' % ns,
        '    for (int k = 0; k < %s::N_INPUTS; ++k) s >> in[k];' % ns,
        '    const bool stable = g.tick(in);',
        '    std::string out;',
        '    for (bool b : g.c) out += b ? \'1\' : \'0\';',
        '    out += stable ? " 1 " : " 0 ";',
        '    for (bool b : %s::outputs(g.c)) out += b ? \'1\' : \'0\';' % ns,
        '    std::cout << out << \'\\n\';',
        '  }',
        '  return 0;',
        '}', ''])


# ------------------------------------------------------------------ ST (IEC 61131-3, as compiled by matiec/OpenPLC)
def gen_st(d, src_sha):
    io = d.io()['located']
    fb = 'FB_GVM_' + d.name
    enum_note = '; '.join('%s: %s' % (n, ', '.join('%d %s' % (k, v) for k, v in enumerate(vals)))
                          for n, vals in d.enum.items())
    hdr = [x[3:] for x in header(d, src_sha, '(*')]
    L = ['(* ' + hdr[0]] + ['   ' + h for h in hdr[1:]] + [
        '   Enumerated inputs as INT indices: %s.' % (enum_note or 'none'),
        '   One scan of PROGRAM Main = one evolution; the situation is kept in the FB instance between scans. *)', '',
        'FUNCTION_BLOCK %s' % fb, '  VAR_INPUT']
    for n, dom in d.inputs:
        L.append('    in_%s : %s;' % (n, 'BOOL' if dom == 'boolean' else 'INT'))
    L += ['  END_VAR', '  VAR_OUTPUT']
    for n in d.outputs:
        L.append('    out_%s : BOOL;' % n)
    L.append('    stable : BOOL;')
    for x, b in zip(d.steps, d.init):
        L.append('    %s : BOOL := %s;' % (x, 'TRUE' if b else 'FALSE'))
    L += ['  END_VAR', '  VAR']
    L.append('    %s : BOOL;' % ', '.join('k_' + x for x in d.steps))
    L.append('    %s : BOOL;' % ', '.join('n_' + x for x in d.steps))
    bools = ['e_' + n for n, dom in d.inputs if dom == 'boolean'] + ['d_' + n for n in d.derived] + \
            ['f_' + t[0] for t in d.trans]
    L.append('    %s : BOOL;' % ', '.join(bools))
    if d.enum:
        L.append('    %s : INT;' % ', '.join('e_' + n for n in d.enum))
    L += ['    first : BOOL;', '    m : INT;', '  END_VAR']
    for x in d.steps:
        L.append('  k_%s := %s;' % (x, x))
    L += ['  FOR m := 1 TO %d DO   (* K = %d micro-steps, then one more for the stability check *)' % (d.K + 1, d.K),
          '    first := m = 1;']
    for kind, tgt, e in d.micro_body('st'):
        if kind == 'set':
            L.append('    %s := %s;' % (tgt, e))
        elif kind == 'cond':
            L.append('    IF %s THEN %s := %s; ELSE %s := %s; END_IF;' % (e[0], tgt, e[1], tgt, e[2]))
        else:
            L.append('    IF %s THEN' % tgt)
            for v, val in e:
                L.append('      %s := %s;' % (v, 'TRUE' if val else 'FALSE'))
            L.append('    END_IF;')
    L.append('    IF m <= %d THEN' % d.K)
    for x in d.steps:
        L.append('      k_%s := k_%s AND n_%s;' % (x, x, x))
    for x in d.steps:
        L.append('      %s := n_%s;' % (x, x))
    L.append('    ELSE')
    L.append('      stable := %s;' % ' AND '.join('(n_%s = %s)' % (x, x) for x in d.steps))
    L += ['    END_IF;', '  END_FOR;']
    for n, e in d.outputs.items():
        L.append('  out_%s := %s;' % (n, d.expr(e, 'st')))
    L += ['END_FUNCTION_BLOCK', '', 'PROGRAM Main', '  VAR']
    for n, dom in d.inputs:
        L.append('    pi_%s AT %s : %s;' % (n, io['in_' + n], 'BOOL' if dom == 'boolean' else 'INT'))
    for n in list(d.outputs) + ['stable']:
        L.append('    po_%s AT %s : BOOL;' % (n, io['out_' + n]))
    for x in d.steps:
        L.append('    px_%s AT %s : BOOL;' % (x, io['x_' + x]))
    L += ['  END_VAR', '  VAR', '    gvm : %s;' % fb, '  END_VAR',
          '  gvm(%s);' % ', '.join('in_%s := pi_%s' % (n, n) for n, _ in d.inputs)]
    for n in d.outputs:
        L.append('  po_%s := gvm.out_%s;' % (n, n))
    L.append('  po_stable := gvm.stable;')
    for x in d.steps:
        L.append('  px_%s := gvm.%s;' % (x, x))
    L += ['END_PROGRAM', '']
    return '\n'.join(L)


def generate(spec_path, out, fault=None, spec=None):
    spec = spec if spec is not None else json.load(open(spec_path, encoding='utf-8'))
    src_sha = desc_sha(spec)
    d = Desc(spec, fault)
    os.makedirs(out, exist_ok=True)
    files = {'%s_gvm.py' % d.name: gen_py(d, src_sha), '%s_gvm.hpp' % d.name: gen_hpp(d, src_sha),
             '%s_gvm_main.cpp' % d.name: gen_main(d, src_sha), '%s_gvm.st' % d.name: gen_st(d, src_sha),
             '%s_gvm_io.json' % d.name: json.dumps(d.io(), indent=1) + '\n'}
    for f, text in files.items():
        open(os.path.join(out, f), 'w', encoding='utf-8').write(text)
    return d, sorted(files)


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('model')
    ap.add_argument('--out', required=True)
    ap.add_argument('--fault', choices=FAULTS)
    a = ap.parse_args()
    d, files = generate(a.model, a.out, a.fault)
    print('%s: %d steps, %d transitions, %d inputs, %d outputs, K = %d; wrote %s' % (
        d.name, len(d.steps), len(d.trans), len(d.inputs), len(d.outputs), d.K, ', '.join(files)))


if __name__ == '__main__':
    main()
