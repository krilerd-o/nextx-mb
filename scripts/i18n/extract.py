import re, glob, json, sys
sys.path.insert(0, sys.argv[1])
from wrap import skip_string
TH = re.compile(r'[฀-๿]')
exact, pats = {}, {}
for f in sorted(glob.glob('lib/**/*.dart', recursive=True)):
    if 'i18n' in f: continue
    s = open(f, encoding='utf-8').read()
    i = 0; n = len(s)
    while i < n:
        c = s[i]
        if s.startswith('//', i): j = s.find('\n', i); i = n if j < 0 else j; continue
        if s.startswith('/*', i): j = s.find('*/', i); i = n if j < 0 else j + 2; continue
        if c in '\'"':
            j = skip_string(s, i)
            lit = s[i:j]
            q = lit[0]
            body = lit[3:-3] if lit.startswith(q*3) else lit[1:-1]
            if TH.search(body):
                body = body.replace("\\'", "'").replace('\\"', '"').replace('\\n', '\n')
                if re.search(r'\$\{|\$[A-Za-z_]', body):
                    tpl = re.sub(r'\$\{(?:[^{}]|\{[^{}]*\})*\}', '{}', body)
                    tpl = re.sub(r'\$[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*', '{}', tpl)
                    pats.setdefault(tpl, f)
                else:
                    exact.setdefault(body, f)
            i = j; continue
        i += 1
json.dump({'exact': exact, 'patterns': pats}, open(sys.argv[2], 'w', encoding='utf-8'), ensure_ascii=False, indent=0)
print(len(exact), 'exact', len(pats), 'patterns')
