"""List Thai UI strings in lib/ that have no English entry in lib/core/i18n_en.dart.

Run from the repo root:  python3 scripts/i18n/missing.py
"""
import json, os, re, subprocess, sys, tempfile

here = os.path.dirname(os.path.abspath(__file__))
out = os.path.join(tempfile.mkdtemp(), 'strings.json')
subprocess.run([sys.executable, os.path.join(here, 'extract.py'), here, out], check=True, stdout=subprocess.DEVNULL)
d = json.load(open(out, encoding='utf-8'))
dart = open('lib/core/i18n_en.dart', encoding='utf-8').read()
keys = set(re.findall(r"^  '((?:[^'\\]|\\.)*)':", dart, re.M))
norm = lambda s: s.replace("\\'", "'").replace('\\n', '\n').replace('\\$', '$').replace('\\\\', '\\')
keys = {norm(k) for k in keys}
miss_e = [k for k in d['exact'] if k not in keys]
miss_p = [k for k in d['patterns'] if k not in keys and re.search('[฀-๿]', k)]
for k in miss_e: print('exact  ', k.replace('\n', '\\n'))
for k in miss_p: print('pattern', k.replace('\n', '\\n'))
print(f'{len(miss_e)} exact, {len(miss_p)} patterns missing', file=sys.stderr)
