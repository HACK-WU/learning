#!/usr/bin/env bash
cd /tmp/consul-ops/tls
python3 - <<'PYEOF'
import json,re
txt=open('probe.json','rb').read().decode('utf-8',errors='replace')

print("== 1. 出现 PRIVATE KEY 的上下文（各截取 300 字符）==")
for i,m in enumerate(re.finditer(r'(PRIVATE KEY|PrivateKey|EC PRIVATE)',txt)):
    s=max(0,m.start()-200); e=min(len(txt),m.end()+400)
    print(f"\n--- 命中 {i+1} at {m.start()} 关键词={m.group()} ---")
    print(repr(txt[s:e])[:700])

print("\n\n== 2. 这是 JSON 数组还是对象？整体结构 ==")
print("  前 300 字符:",repr(txt[:300]))
print("  后 200 字符:",repr(txt[-200:]))

print("\n== 3. 尝试按行解析每个 JSON 对象 ==")
dec=json.JSONDecoder()
i=0; objs=[]
while i < len(txt):
    while i<len(txt) and txt[i] in ' \n\r\t': i+=1
    if i>=len(txt): break
    try:
        o,j=dec.raw_decode(txt,i)
        objs.append(o); i=j
    except Exception:
        # 跳过到下一个 {
        k=txt.find('{',i)
        if k<0: break
        i=k
print(f"  解析出 {len(objs)} 个顶层对象")
for n,o in enumerate(objs[:12]):
    if isinstance(o,dict):
        keys=list(o.keys())
        print(f"   [{n}] keys={keys[:8]}")
PYEOF
