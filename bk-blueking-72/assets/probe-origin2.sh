#!/usr/bin/env bash
NS=blueking
kubectl get secret -n $NS sh.helm.release.v1.bk-repo.v1 -o jsonpath='{.data.release}' 2>/dev/null \
 | base64 -d 2>/dev/null | base64 -d 2>/dev/null | gunzip 2>/dev/null > /tmp/bk.json

python3 - <<'PY'
import json,re
raw=open('/tmp/bk.json',encoding='utf-8',errors='ignore').read()
# release JSON: {name, info, manifest, ...}  manifest 是完整 k8s yaml 拼接
try:
    j=json.loads(raw)
    man=j.get('manifest','')
except Exception as e:
    print('  json 解析失败:',e); raise SystemExit

print('  manifest 长度:',len(man))

# manifest 是多个 yaml 文档，按 kind: Deployment 切块
docs=[d for d in man.split('\n---\n') if 'kind: Deployment' in d]
print('  Deployment 文档数:',len(docs))
print('')

for d in docs:
    nm=re.search(r'name:\s*(bkrepo-[\w-]+)', d)
    if not nm: continue
    name=nm.group(1)
    # 找 containers 下的 livenessProbe（缩进最深的那个）
    lm=re.search(r'^(\s+)livenessProbe:', d, re.M)
    if not lm:
        print('  %-28s 无 livenessProbe'%name); continue
    ind=len(lm.group(1))
    # 取该块（缩进 > ind 的连续行）
    lines=d[lm.end():].split('\n')
    block=[]
    for l in lines:
        if l.strip() and (len(l)-len(l.lstrip()))<=ind: break
        block.append(l)
    t='\n'.join(block)
    init=re.search(r'initialDelaySeconds:\s*(\d+)',t)
    fail=re.search(r'failureThreshold:\s*(\d+)',t)
    per =re.search(r'periodSeconds:\s*(\d+)',t)
    print('  %-28s init=%-5s fail=%-3s period=%s'%(name,
        init.group(1) if init else '-', fail.group(1) if fail else '-', per.group(1) if per else '-'))
PY
