#!/usr/bin/env bash
NS=blueking

echo "=== 从 helm release 提取 bkrepo 各组件权威原值 ==="
kubectl get secret -n $NS sh.helm.release.v1.bk-repo.v1 -o jsonpath='{.data.release}' 2>/dev/null \
 | base64 -d 2>/dev/null | base64 -d 2>/dev/null | gunzip 2>/dev/null > /tmp/bkrepo-rel.json 2>/dev/null

[ -s /tmp/bkrepo-rel.json ] && echo "  已释放 $(wc -c </tmp/bkrepo-rel.json) 字节" || echo "  [失败] 拿不到 release"

python3 - <<'PY'
import json,re
try:
    raw=open('/tmp/bkrepo-rel.json',encoding='utf-8',errors='ignore').read()
except:
    print('  读不到'); raise SystemExit

# release 里 manifest 是转义过的字符串，逐个组件找 liveness
for name in ['auth','gateway','repository','docker','helm','maven','npm','pypi','job','opdata','replication']:
    # 找该组件 deploy 段
    idx=raw.find('bkrepo-'+name)
    if idx<0: continue
    seg=raw[idx:idx+9000]
    m=re.search(r'livenessProbe.{0,600}', seg, re.S)
    if not m: 
        print('  %-14s 无 liveness'%name); continue
    t=m.group(0)
    # 在第一个 readinessProbe 之前截断，避免串到 readiness
    cut=t.find('readinessProbe')
    if cut>0: t=t[:cut]
    init=re.search(r'initialDelaySeconds[":\s]+(\d+)', t)
    fail=re.search(r'failureThreshold[":\s]+(\d+)', t)
    per=re.search(r'periodSeconds[":\s]+(\d+)', t)
    print('  %-14s init=%-5s fail=%-3s period=%s' % (
        name, init.group(1) if init else '?', fail.group(1) if fail else '?', per.group(1) if per else '?'))
PY
