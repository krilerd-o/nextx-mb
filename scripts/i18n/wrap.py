"""Route display strings through tr()/trn(): Text(...) first arg, TextSpan(text:), and
hintText/labelText/helperText/errorText/tooltip named args. Usage: wrap.py <dart files...>"""
import re, sys

IDCH = re.compile(r'[A-Za-z0-9_$.]')

def skip_string(s, i):
    """s[i] is a quote (maybe after r prefix). returns index after the literal."""
    raw = False
    if s[i] in 'rR':
        raw = True; i += 1
    q = s[i]
    triple = s[i:i+3] == q*3
    if triple:
        i += 3
        while i < len(s):
            if not raw and s[i] == '\\': i += 2; continue
            if not raw and s[i] == '$' and i+1 < len(s) and s[i+1] == '{':
                i = skip_braces(s, i+1); continue
            if s[i:i+3] == q*3: return i+3
            i += 1
        return i
    i += 1
    while i < len(s):
        c = s[i]
        if not raw and c == '\\': i += 2; continue
        if not raw and c == '$' and i+1 < len(s) and s[i+1] == '{':
            i = skip_braces(s, i+1); continue
        if c == q: return i+1
        if c == '\n': return i
        i += 1
    return i

def skip_braces(s, i):
    """s[i]=='{' ; return index after matching '}' (code inside)."""
    depth = 0
    while i < len(s):
        c = s[i]
        if c in '\'"': i = skip_string(s, i); continue
        if s.startswith('//', i): i = s.find('\n', i); i = len(s) if i < 0 else i; continue
        if s.startswith('/*', i): j = s.find('*/', i); i = len(s) if j < 0 else j+2; continue
        if c == '{': depth += 1
        elif c == '}':
            depth -= 1
            if depth == 0: return i+1
        i += 1
    return i

def expr_end(s, i):
    """from i (start of an argument expression) to index of ',' or ')' at depth 0."""
    depth = 0
    while i < len(s):
        c = s[i]
        if c in '\'"' or (c in 'rR' and i+1 < len(s) and s[i+1] in '\'"' and not IDCH.match(s[i-1])):
            i = skip_string(s, i); continue
        if s.startswith('//', i): i = s.find('\n', i); continue
        if s.startswith('/*', i): i = s.find('*/', i) + 2; continue
        if c in '([{': depth += 1
        elif c in ')]}':
            if depth == 0: return i
            depth -= 1
        elif c == ',' and depth == 0: return i
        i += 1
    return i

NAMED = ('hintText', 'labelText', 'helperText', 'errorText', 'tooltip')
CALLS = ('Text', 'SelectableText', 'NxStreamingText')

def process(s):
    out = []; i = 0; n = len(s); changed = 0
    while i < n:
        c = s[i]
        # strings / comments copied verbatim
        if c in '\'"' or (c in 'rR' and i+1 < n and s[i+1] in '\'"' and (i == 0 or not IDCH.match(s[i-1]))):
            j = skip_string(s, i); out.append(s[i:j]); i = j; continue
        if s.startswith('//', i):
            j = s.find('\n', i); j = n if j < 0 else j; out.append(s[i:j]); i = j; continue
        if s.startswith('/*', i):
            j = s.find('*/', i); j = n if j < 0 else j+2; out.append(s[i:j]); i = j; continue
        prev = s[i-1] if i > 0 else ' '
        hit = None
        if not IDCH.match(prev):
            for name in CALLS:
                if s.startswith(name + '(', i):
                    hit = ('call', name); break
            if not hit:
                for name in NAMED + ('text',):
                    m = re.match(name + r'\s*:', s[i:])
                    if m and (name != 'text' or _in_textspan(s, i)):
                        hit = ('named', m.group(0)); break
        if hit and hit[0] == 'call':
            start = i + len(hit[1]) + 1
            out.append(s[i:start]); i = start
            k = i
            while k < n and s[k] in ' \n\t': k += 1
            # named first arg (Text(key: ...)) or empty → leave
            if re.match(r'[A-Za-z_]\w*\s*:(?!:)', s[k:]) or s[k] == ')':
                continue
            e = expr_end(s, k)
            expr = s[k:e]
            if not expr.strip().startswith(('tr(', 'trn(')):
                out.append(s[i:k] + 'tr(' + expr.rstrip() + ')' + expr[len(expr.rstrip()):])
                changed += 1
            else:
                out.append(s[i:e])
            i = e
            continue
        if hit and hit[0] == 'named':
            label = hit[1]
            out.append(label); i += len(label)
            k = i
            while k < n and s[k] in ' \n\t': k += 1
            e = expr_end(s, k)
            expr = s[k:e]
            if expr.strip() and not expr.strip().startswith(('tr(', 'trn(')) and expr.strip() != 'null':
                out.append(s[i:k] + 'trn(' + expr.rstrip() + ')' + expr[len(expr.rstrip()):])
                changed += 1
            else:
                out.append(s[i:e])
            i = e
            continue
        out.append(c); i += 1
    return ''.join(out), changed

def _in_textspan(s, i):
    j = s.rfind('(', 0, i)
    return j >= 8 and s[max(0, j-8):j].endswith('TextSpan')

if __name__ == '__main__':
    total = 0
    for f in sys.argv[1:]:
        src = open(f, encoding='utf-8').read()
        new, ch = process(src)
        if ch:
            if "core/i18n.dart'" not in new:
                depth = f.count('/') - 1
                rel = ('../' * (depth - 1)) + 'core/i18n.dart' if not f.startswith('lib/core/') else 'i18n.dart'
                imports = list(re.finditer(r"^import [^\n]+\n", new, re.M))
                pos = imports[-1].end() if imports else 0
                new = new[:pos] + "import '" + rel + "';\n" + new[pos:]
            open(f, 'w', encoding='utf-8').write(new)
            total += ch
    print('wrapped', total)
