#!/usr/bin/env python3
"""Write a CI secret to a file. Accepts base64 (with stray spaces / line breaks /
Windows CRLF / data-URL prefix) or the raw file content (JSON, PEM, plist).
Never prints the secret; on failure says which secret and why.

usage: secret_file.py ENV_NAME OUTPUT_PATH [json|pem|plist|binary]
"""
import base64
import binascii
import os
import re
import sys

name, out = sys.argv[1], sys.argv[2]
kind = sys.argv[3] if len(sys.argv) > 3 else 'binary'
raw = os.environ.get(name, '')
text = raw.strip().lstrip('﻿')

def looks_raw(t):
    return (kind == 'json' and t.startswith('{')) or \
           (kind == 'pem' and t.startswith('-----BEGIN')) or \
           (kind == 'plist' and t.startswith('<?xml'))

if not text:
    sys.exit(f'::error::Secret {name} is empty.')

if looks_raw(text):
    data = text.encode()
    how = 'raw text'
else:
    t = re.sub(r'^data:[^,]*,', '', text)
    t = re.sub(r'\s+', '', t)
    if t.startswith('"') and t.endswith('"'):
        t = t[1:-1]
    t = t.replace('-', '+').replace('_', '/')
    t += '=' * (-len(t) % 4)
    bad = sorted(set(re.findall(r'[^A-Za-z0-9+/=]', t)))
    if bad:
        sys.exit(f'::error::Secret {name} is not base64: it contains {len(bad)} unexpected character type(s) '
                 f'(length {len(raw)}). Re-copy the whole content of the .txt file and paste it again.')
    try:
        data = base64.b64decode(t, validate=True)
    except (binascii.Error, ValueError) as e:
        sys.exit(f'::error::Secret {name} is not valid base64 ({e}). Re-copy and paste it again.')
    how = 'base64'

checks = {
    'json': lambda d: d.lstrip().startswith(b'{'),
    'pem': lambda d: b'-----BEGIN' in d,
    'plist': lambda d: b'<plist' in d or d.startswith(b'bplist'),
}
if kind in checks and not checks[kind](data):
    sys.exit(f'::error::Secret {name} decoded ({how}) but is not a {kind} file — was the wrong file pasted?')

os.makedirs(os.path.dirname(out) or '.', exist_ok=True)
with open(out, 'wb') as f:
    f.write(data)
print(f'{name}: wrote {len(data)} bytes to {out} ({how})')
