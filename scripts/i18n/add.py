"""Append translations to lib/core/i18n_en.dart.

Input (stdin): one `thai<TAB>english` per line. Lines whose Thai has `{}`
go to enPatterns, the rest to enStrings. Existing keys are skipped.
Usage: python3 scripts/i18n/add.py < new.tsv
"""
import re, sys

p = 'lib/core/i18n_en.dart'
s = open(p, encoding='utf-8').read()
def q(x): return "'" + x.replace('\\', '\\\\').replace("'", "\\'").replace('$', '\\$').replace('\n', '\\n') + "'"
have = set(re.findall(r"^  ('(?:[^'\\]|\\.)*'):", s, re.M))
ex, pa = [], []
for line in sys.stdin:
    line = line.rstrip('\n')
    if '\t' not in line: continue
    th, en = line.split('\t', 1)
    th = th.replace('⏎', '\n'); en = en.replace('⏎', '\n')
    if q(th) in have: continue
    have.add(q(th))
    (pa if '{}' in th else ex).append(f'  {q(th)}: {q(en)},\n')
a = s.index('};\n\n/// Thai templates')
s = s[:a] + ''.join(ex) + s[a:]
s = s.rstrip()
s = s[:-2] + ''.join(pa) + '};\n'
open(p, 'w', encoding='utf-8').write(s)
print(f'added {len(ex)} exact, {len(pa)} patterns')
