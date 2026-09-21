#!/usr/bin/env python3
import gzip, re
p = '/tmp/consul-ops/tls/probe.snap'
txt = gzip.decompress(open(p, 'rb').read()).decode('utf-8', errors='replace')
out = []
out.append(f"解压后 {len(txt)} 字符")
for m in re.finditer(r'(PRIVATE KEY|PrivateKey|EC PRIVATE)', txt):
    s = max(0, m.start() - 150)
    e = min(len(txt), m.end() + 250)
    out.append(f"@{m.start()} [{m.group()}] :: " + txt[s:e].replace('\n', '|')[:380])
open('/tmp/consul-ops/tls/probe.out', 'w').write('\n'.join(out))
print("OK")
