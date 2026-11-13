#!/usr/bin/env python3
"""Scene-test parameters (scene_tests_en.md): before a program is uploaded for one situation of the scene test, set
the initial values of the parameters that the task card names, in the upload file written by compile_check.py.

  T2 (a), (c)        TimerDuration := T#15s        (the level reaches LSH after about 30 s)
  T2 (b)             TimerDuration := T#60s        (LSHH ends filling first, after about 34 s)
  T3 (a), (b)        TON_Duration := T#5s; TOF_Duration := T#5s
  T4 (a), (b), (c)   Kp := 5.0; Ti := 40.0; Td := 0.0

Every declaration of exactly these identifiers (IEC identifiers are case-insensitive) with the expected type (TIME, or
REAL / LREAL) gets the value, whether or not it had an initial value; declarations inside comments, declarations of
several variables in one line, and everything else of the program are left unchanged.  A parameter that the program
does not declare is reported, and the program then runs with its own value.  The compile check (compiled,
a2_compiled) is not affected: it always uses the program as generated.  Store the printed log in test_log.

  python3 set_params.py PROG_openplc.st T2 a        # writes PROG_openplc_T2a.st and prints the log
  python3 set_params.py --selftest
"""
import argparse
import hashlib
import os
import re
import sys

SCENARIOS = {
    ('T2', 'a'): {'TimerDuration': ('TIME', 'T#15s')},
    ('T2', 'b'): {'TimerDuration': ('TIME', 'T#60s')},
    ('T2', 'c'): {'TimerDuration': ('TIME', 'T#15s')},
    ('T3', 'a'): {'TON_Duration': ('TIME', 'T#5s'), 'TOF_Duration': ('TIME', 'T#5s')},
    ('T3', 'b'): {'TON_Duration': ('TIME', 'T#5s'), 'TOF_Duration': ('TIME', 'T#5s')},
    ('T4', 'a'): {'Kp': ('REAL', '5.0'), 'Ti': ('REAL', '40.0'), 'Td': ('REAL', '0.0')},
    ('T4', 'b'): {'Kp': ('REAL', '5.0'), 'Ti': ('REAL', '40.0'), 'Td': ('REAL', '0.0')},
    ('T4', 'c'): {'Kp': ('REAL', '5.0'), 'Ti': ('REAL', '40.0'), 'Td': ('REAL', '0.0')},
}
TYPES = {'TIME': ('TIME',), 'REAL': ('REAL', 'LREAL')}


def comment_mask(text):
    """True for every character inside a (* *) comment."""
    mask = [False] * len(text)
    for m in re.finditer(r'\(\*.*?\*\)', text, re.S):
        for i in range(m.start(), m.end()):
            mask[i] = True
    return mask


def set_params(text, params):
    """Return (new text, log lines)."""
    mask = comment_mask(text)
    log = []
    edits = []
    for name, (kind, value) in params.items():
        pat = re.compile(r'(?im)^([ \t]*)(%s)([ \t]*:[ \t]*)(%s)\b([ \t]*:=[ \t]*([^;\n]*?))?([ \t]*;)'
                         % (re.escape(name), '|'.join(TYPES[kind])))
        found = 0
        for m in pat.finditer(text):
            if mask[m.start(2)]:
                continue
            found += 1
            line = text.count('\n', 0, m.start()) + 1
            old = (m.group(6) or '').strip() or '(none)'
            new = '%s%s%s%s := %s;' % (m.group(1), m.group(2), m.group(3), m.group(4), value)
            edits.append((m.start(), m.end(), new))
            log.append('set %s (line %d, %s): %s -> %s' % (m.group(2), line, m.group(4).upper(), old, value))
        shared = re.search(r'(?im)^[ \t]*\w+(?:[ \t]*,[ \t]*\w+)*[ \t]*,[ \t]*%s\b|^[ \t]*%s[ \t]*,' % (re.escape(name), re.escape(name)), text)
        if shared and not mask[shared.start()]:
            log.append('not changed: %s is declared together with other variables (line %d)'
                       % (name, text.count('\n', 0, shared.start()) + 1))
        elif not found:
            log.append('not declared: %s (the program runs with its own value)' % name)
    for start, end, new in sorted(edits, reverse=True):
        text = text[:start] + new + text[end:]
    return text, log


def run(path, task, case):
    params = SCENARIOS[(task, case)]
    raw = open(path, encoding='utf-8').read()
    out_text, log = set_params(raw, params)
    base, ext = os.path.splitext(path)
    out = '%s_%s%s%s' % (base, task, case, ext)
    open(out, 'w', encoding='utf-8').write(out_text)
    head = ['file: %s  sha256: %s' % (os.path.basename(path), hashlib.sha256(raw.encode()).hexdigest()),
            'scenario: %s (%s)' % (task, case)]
    tail = ['output: %s  sha256: %s' % (os.path.basename(out), hashlib.sha256(out_text.encode()).hexdigest())]
    return out, head + log + tail


SELFTEST = '''FUNCTION_BLOCK FB_X
  VAR_INPUT
    timerduration : TIME;          (* TimerDuration : TIME := T#1s; inside a comment *)
  END_VAR
END_FUNCTION_BLOCK
PROGRAM Main
  VAR
    TimerDuration : TIME := T#30s;
    KP : REAL := 1.0;
    Ti, Td : REAL;
    other : TIME := T#2s;
  END_VAR
END_PROGRAM
'''


def selftest():
    ok = True
    text, log = set_params(SELFTEST, SCENARIOS[('T2', 'b')])
    ok &= text.count('T#60s') == 2 and 'T#1s' in text and 'T#2s' in text
    ok &= sum(l.startswith('set TimerDuration') or l.startswith('set timerduration') for l in log) == 2
    text4, log4 = set_params(SELFTEST, SCENARIOS[('T4', 'a')])
    ok &= 'KP : REAL := 5.0;' in text4 and 'Ti, Td : REAL;' in text4
    ok &= any(l.startswith('not changed: Ti') for l in log4) and any(l.startswith('not changed: Td') for l in log4)
    text3, log3 = set_params(SELFTEST, SCENARIOS[('T3', 'a')])
    ok &= text3 == SELFTEST and sum(l.startswith('not declared') for l in log3) == 2
    for l in log + log4 + log3:
        print('   ' + l)
    print('selftest:', 'passed' if ok else 'FAILED')
    return ok


def main():
    ap = argparse.ArgumentParser(description='Set the scene-test parameters of an upload file.')
    ap.add_argument('file', nargs='?')
    ap.add_argument('task', nargs='?', choices=['T2', 'T3', 'T4'])
    ap.add_argument('case', nargs='?', choices=['a', 'b', 'c'])
    ap.add_argument('--selftest', action='store_true')
    a = ap.parse_args()
    if a.selftest:
        sys.exit(0 if selftest() else 1)
    if not (a.file and a.task and a.case) or (a.task, a.case) not in SCENARIOS:
        ap.error('give FILE TASK CASE, for example prog_openplc.st T2 a')
    out, log = run(a.file, a.task, a.case)
    print('\n'.join(log))


if __name__ == '__main__':
    main()
