#!/usr/bin/env python3
import gzip, json, re, os
p = '/tmp/consul-ops/tls/probe.snap'
raw = open(p, 'rb').read()
d = gzip.decompress(raw)
txt = d.decode('utf-8', errors='replace')
print(f"原始 {len(raw)} → 解压 {len(d)} 字节")

# 找所有私钥命中位置的上下文
print("\n===== 私钥关键字命中上下文 =====")
for i, m in enumerate(re.finditer(r'(PRIVATE KEY|PrivateKey|EC PRIVATE)', txt)):
    s = max(0, m.start() - 250)
    e = min(len(txt), m.end() + 500)
    print(f"\n----- 命中 {i+1} @{m.start()} 关键词={m.group()} -----")
    print(txt[s:e].replace('\n', '\\n')[:800])

print("\n\n===== 整体结构 =====")
print("前 200:", repr(txt[:200]))
print("后 150:", repr(txt[-150:]))

# 尝试切分多个 JSON 对象
print("\n===== 切分顶层 JSON 对象 =====")
dec = json.JSONDecoder()
i = 0
objs = []
while i < len(txt):
    while i < len(txt) and txt[i] in ' \n\r\t':
        i += 1
    if i >= len(txt):
        break
    try:
        o, j = dec.raw_decode(txt, i)
        objs.append(o)
        i = j
    except Exception:
        k = txt.find('{', i)
        if k < 0:
            break
        i = k
print(f"解析出 {len(objs)} 个顶层对象")
for n, o in enumerate(objs):
    if isinstance(o, dict):
        keys = list(o.keys())
        print(f"  [{n}] keys={keys[:10]}")
        # 深入：如果含 connect/ca 相关，打印
        for kk in keys:
            if any(x in kk.lower() for x in ['connect', 'ca', 'cert', 'key', 'root']):
                v = o[kk]
                vs = str(v)
                print(f"        {kk} = {vs[:300]}")
