#!/usr/bin/env bash
export CONSUL_HTTP_ADDR=http://127.0.0.1:8501
cd /tmp/consul-ops/tls
python3 - <<'PYEOF'
import gzip,json,re
raw=open('probe.snap','rb').read()
d=gzip.decompress(raw)
print(f"原始 {len(raw)} → 解压 {len(d)} 字节")
open('probe.json','wb').write(d)
txt=d.decode('utf-8',errors='replace')

print("\n== 搜私钥关键字 ==")
for kw in ["PRIVATE KEY","private_key","PrivateKey","BEGIN RSA","EC PRIVATE"]:
    print(f"  {kw!r:20s} 出现 {txt.count(kw)} 次")

print("\n== 顶层结构 ==")
try:
    j=json.loads(txt); print("  顶层键:",list(j.keys()))
except Exception as e:
    print("  非纯 JSON，取键名:",sorted(set(re.findall(r'"([A-Za-z_]{3,30})":',txt)))[:25])

print("\n== 快照里有什么（关键内容）==")
for kw in ["ConnectCA","connect","ca_root","CARoot","index","KV","Nodes","Services","acl","token","Session"]:
    c=txt.count(kw)
    if c: print(f"  {kw:12s} 出现 {c} 次")

print("\n== 结论判据 ==")
has_pk = any(k in txt for k in ["PRIVATE KEY","private_key","PrivateKey","BEGIN RSA","EC PRIVATE"])
print(f"  含私钥内容: {has_pk}")
print("  → 若为 False，即证实官方说法：快照不含 Connect CA 私钥")
PYEOF
