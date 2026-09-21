#!/usr/bin/env python3
import gzip, re
p = '/tmp/consul-ops/tls/probe.snap'
txt = gzip.decompress(open(p, 'rb').read()).decode('utf-8', errors='replace')
out = []

# 真私钥出现位置
pk = [m.start() for m in re.finditer(r'-----BEGIN EC PRIVATE KEY-----', txt)]
out.append(f"真 EC PRIVATE KEY 出现 {len(pk)} 次 @ {pk}")

# 找最近的 RootCert 与 ID 字段
for pos in pk:
    # 向前找最近的 ID
    seg_before = txt[max(0, pos-3000):pos]
    ids = [(m.start()+max(0,pos-3000), m.group()) for m in re.finditer(r'ID\x06.{0,80}', seg_before)]
    out.append(f"\n--- 私钥@{pos} 前方最近 ID 字段 ---")
    for s, g in ids[-3:]:
        out.append(f"  @{s}: {g[:120]!r}")
    # 向后看 200
    out.append(f"  后方: {txt[pos:pos+200]!r}")

# 列出所有 ID 出现位置及其后内容（判断有几个 CA 对象）
out.append("\n===== 所有 ID 字段 =====")
for m in re.finditer(r'ID\x06', txt):
    s = m.start()
    out.append(f"  @{s}: {txt[s:s+90]!r}")

open('/tmp/consul-ops/tls/probe4.out', 'w').write('\n'.join(out))
print("OK")
