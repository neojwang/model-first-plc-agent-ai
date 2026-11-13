#!/usr/bin/env python3
"""Fill a prompt template with a task card (and, for later stages, the earlier response of the same lane).

  python3 render_prompt.py T2 A1_1_idef0                              > prompt.txt
  python3 render_prompt.py T2 A1_2_grafcet --idef0 a1_idef0.md         > prompt.txt
  python3 render_prompt.py T2 A1_3_st      --grafcet a1_grafcet.json   > prompt.txt
  python3 render_prompt.py T2 B_st                                     > prompt.txt
The A2 lane (A2_1, A2_2, A2_3) must run in a new conversation that has not seen the A1 artifacts.
"""
import argparse
import os

HERE = os.path.dirname(os.path.abspath(__file__))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('task', choices=['T1', 'T2', 'T3', 'T4'])
    ap.add_argument('template', choices=['A1_1_idef0', 'A1_2_grafcet', 'A1_3_st', 'A2_1_idef0', 'A2_2_grafcet',
                                         'A2_3_st', 'B_st'])
    ap.add_argument('--idef0')
    ap.add_argument('--grafcet')
    a = ap.parse_args()
    read = lambda p: open(p, encoding='utf-8').read().strip()
    text = read(os.path.join(HERE, 'prompts', 'templates', a.template + '.md'))
    fills = {'{TASK_CARD}': read(os.path.join(HERE, 'prompts', 'tasks', a.task + '.md')),
             '{SCHEMA}': read(os.path.join(HERE, 'prompts', 'templates', '_schema.md'))}
    if '{IDEF0_MODEL}' in text:
        assert a.idef0, 'this stage needs --idef0 (the IDEF0 response of the same lane)'
        fills['{IDEF0_MODEL}'] = read(a.idef0)
    if '{GRAFCET_JSON}' in text:
        assert a.grafcet, 'this stage needs --grafcet (the GRAFCET JSON of the same lane)'
        fills['{GRAFCET_JSON}'] = read(a.grafcet)
    for k, v in fills.items():
        text = text.replace(k, v)
    print(text)


if __name__ == '__main__':
    main()
