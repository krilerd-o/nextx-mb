import re,sys,json
L='/home/user/nextx/frontend/src/i18n/locales/'
pat=re.compile(r"^\s*'((?:journey|sj)\.[^']+)':\s*'((?:[^'\\]|\\.)*)',?\s*$")
pat2=re.compile(r'^\s*\'((?:journey|sj)\.[^\']+)\':\s*"((?:[^"\\]|\\.)*)",?\s*$')
def load(f):
    d={}
    for line in open(L+f,encoding='utf8'):
        m=pat.match(line) or pat2.match(line)
        if m: d[m.group(1)]=m.group(2).replace("\\'","'").replace('\\"','"')
    return d
th=load('th.js'); en=load('en.js')
keys=sorted(set(th)|set(en))
def q(s): return "'"+s.replace('\\','\\\\').replace("'","\\'").replace('$','\\$')+"'"
out=['// GENERATED from NEXTX frontend i18n (journey.* / sj.*) by tool/gen_journey_text.py — do not edit by hand.','// ignore_for_file: lines_longer_than_80_chars','','const Map<String, List<String>> kJourneyText = {']
for k in keys:
    out.append(f"  {q(k)}: [{q(th.get(k, en.get(k,'')))}, {q(en.get(k, th.get(k,'')))}],")
out.append('};')
open(sys.argv[1],'w').write('\n'.join(out)+'\n')
print(len(keys), len(th), len(en))
