#!/usr/bin/env python3
import gzip, re
p = '/tmp/consul-ops/tls/probe.snap'
txt = gzip.decompress(open(p, 'rb').read()).decode('utf-8', errors='replace')
out = []
out.append(f"总长 {len(txt)}")

# 区分：PrivateKeyBits/PrivateKeyType（元数据）vs PrivateKey（真值）
for kw in ['PrivateKeyBits', 'PrivateKeyType', 'PrivateKey\xa0', 'IntermediateCerts', 'IntermediateCert\xa0', 'RootCert', 'CAConfig', 'Provider', 'LeafCert', 'ConnectCA', 'CARoot']:
    idxs = [m.start() for m in re.finditer(re.escape(kw), txt)]
    out.append(f"{kw!r:22s} 命中 {len(idxs)} 次 @ {idxs[:8]}")

# 定位真私钥对象的完整上下文（前后各 1200）
m = re.search(r'PrivateKey\xa0', txt)
if m:
    s = max(0, m.start() - 1200)
    e = min(len(txt), m.end() + 300)
    out.append("\n===== 真 PrivateKey 对象上下文（前1200后300）=====")
    out.append(txt[s:e].replace('\n', '|'))

open('/tmp/consul-ops/tls/probe3.out', 'w').write('\n'.join(out))
print("OK")
