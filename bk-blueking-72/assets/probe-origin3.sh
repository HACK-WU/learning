#!/usr/bin/env bash
NS=blueking
kubectl get secret -n $NS sh.helm.release.v1.bk-repo.v1 -o jsonpath='{.data.release}' 2>/dev/null \
 | base64 -d 2>/dev/null | base64 -d 2>/dev/null | gunzip 2>/dev/null > /tmp/bk.json
kubectl get secret -n $NS sh.helm.release.v1.bk-monitor.v1 -o jsonpath='{.data.release}' 2>/dev/null \
 | base64 -d 2>/dev/null | base64 -d 2>/dev/null | gunzip 2>/dev/null > /tmp/bkm.json

python3 - <<'PY'
import json,re

def scan(path,title):
    print('=== %s ==='%title)
    try:
        j=json.loads(open(path,encoding='utf-8',errors='ignore').read())
        man=j.get('manifest','')
    except Exception as e:
        print('  解析失败',e); return
    docs=[d for d in man.split('\n---\n') if 'kind: Deployment' in d]
    for d in docs:
        nm=re.search(r'name:\s*(bk[\w-]{4,60})', d)
        name=nm.group(1) if nm else '?'
        lm=re.search(r'^(\s+)livenessProbe:', d, re.M)
        if not lm:
            print('  %-36s 无 livenessProbe'%name); continue
        ind=len(lm.group(1))
        block=[]
        for l in d[lm.end():].split('\n'):
            if l.strip() and (len(l)-len(l.lstrip()))<=ind: break
            block.append(l)
        t='\n'.join(block)
        init=re.search(r'initialDelaySeconds:\s*(\d+)',t)
        fail=re.search(r'failureThreshold:\s*(\d+)',t)
        per =re.search(r'periodSeconds:\s*(\d+)',t)
        print('  %-36s init=%-5s fail=%-3s period=%s'%(name,
            init.group(1) if init else '-', fail.group(1) if fail else '-', per.group(1) if per else '-'))
    print('')

scan('/tmp/bk.json','bk-repo (12 个 deploy)')
PY
