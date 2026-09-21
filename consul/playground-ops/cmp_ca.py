#!/usr/bin/env python3
import json, os
D = '/tmp/consul-ops/tls'
def load(fn):
    try:
        return json.load(open(os.path.join(D, fn)))
    except Exception as e:
        print(f"  {fn} 读取失败: {e}")
        return None

b = load('roots_before.json')
n = load('roots_new.json')
out = []
if b:
    out.append(f"恢复前 ActiveRootID = {b.get('ActiveRootID')}")
if n:
    out.append(f"新集群 ActiveRootID = {n.get('ActiveRootID')}")
if b and n:
    same = b.get('ActiveRootID') == n.get('ActiveRootID')
    out.append(f"两者相同? {same}  → {'相同说明CA被快照还原' if same else '不同说明新集群生成了全新CA'}")
open(f'{D}/cmp.out', 'w').write('\n'.join(out))
print('\n'.join(out))
