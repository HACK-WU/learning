#!/usr/bin/env python3
import json, os
D = '/tmp/consul-ops/tls'
def load(fn):
    try:
        return json.load(open(os.path.join(D, fn)))
    except Exception as e:
        return None

b = load('roots_before.json')       # 快照前
n = load('roots_new.json')          # 新集群（恢复前）
r = load('roots_restored.json')     # 恢复后

def rid(x):
    return x.get('ActiveRootID') if x else None

out = []
out.append("=" * 64)
out.append(f"快照前   ActiveRootID = {rid(b)}")
out.append(f"新集群   ActiveRootID = {rid(n)}")
out.append(f"恢复后   ActiveRootID = {rid(r)}")
out.append("=" * 64)

if b and r:
    back = rid(b) == rid(r)
    out.append(f"恢复后 == 快照前 ? {back}")
    if back:
        out.append(">>> 结论：CA 被快照还原了！快照【包含】CA 私钥(或至少CA根)")
        out.append(">>> 这与『官方说快照不含 CA 私钥』矛盾 → 需进一步区分")
    else:
        out.append(">>> 结论：CA 未被还原 → 快照【不含】CA 私钥")
        out.append(">>> 官方说法成立：恢复后 CA 是新集群自己生成的")

# 对比根证书内容是否一致
if b and r:
    rb = b.get('Roots', [{}])[0].get('RootCert', '')
    rr = r.get('Roots', [{}])[0].get('RootCert', '')
    out.append(f"RootCert 内容一致? {rb == rr}")
    out.append(f"  快照前 RootCert 前60: {rb[:60]}")
    out.append(f"  恢复后 RootCert 前60: {rr[:60]}")

open(f'{D}/cmp_all.out', 'w').write('\n'.join(out))
print('\n'.join(out))
