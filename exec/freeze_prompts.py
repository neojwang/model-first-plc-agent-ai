#!/usr/bin/env python3
"""Freeze the prompts before the experiment: SHA-256 of every task card and template.

  python3 freeze_prompts.py            # writes prompts_manifest.json (run once, before the first generation)
  python3 freeze_prompts.py --verify   # exits with status 1 if any prompt file changed since freezing
"""
import hashlib
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, 'prompts')
MANIFEST = os.path.join(HERE, 'prompts_manifest.json')


def digest_all():
    out = {}
    for sub in ('tasks', 'templates'):
        for name in sorted(os.listdir(os.path.join(ROOT, sub))):
            p = os.path.join(ROOT, sub, name)
            out['%s/%s' % (sub, name)] = hashlib.sha256(open(p, 'rb').read()).hexdigest()
    return out


def main():
    cur = digest_all()
    if '--verify' in sys.argv[1:]:
        old = json.load(open(MANIFEST, encoding='utf-8'))['sha256']
        changed = sorted(k for k in set(old) | set(cur) if old.get(k) != cur.get(k))
        print('changed since freezing: %s' % (', '.join(changed) if changed else 'none'))
        sys.exit(1 if changed else 0)
    json.dump({'sha256': cur}, open(MANIFEST, 'w', encoding='utf-8'), indent=1)
    print('froze %d prompt files into %s' % (len(cur), MANIFEST))


if __name__ == '__main__':
    main()
