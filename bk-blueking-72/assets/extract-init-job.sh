#!/usr/bin/env bash
set -uo pipefail
NS=blueking

echo "===== 提取 bkrepo chart 的 init-job 模板 ====="
kubectl get secret sh.helm.release.v1.bk-repo.v1 -n $NS -o jsonpath='{.data.release}' 2>/dev/null | base64 -d 2>/dev/null | base64 -d 2>/dev/null | python3 -c "
import sys,gzip,json,base64,re
raw=sys.stdin.buffer.read()
data=raw
try: data=gzip.decompress(raw)
except Exception: pass
j=json.loads(data)
ch=j.get('chart',{})
files={}
for f in (ch.get('templates',[]) or [])+(ch.get('files',[]) or []):
    nm=f.get('name','')
    d=f.get('data','')
    try: files[nm]=base64.b64decode(d).decode('utf-8','ignore')
    except Exception: files[nm]=d
for nm in ['templates/init-job/init-mongodb.yaml','templates/init-job/init-entrance.yaml','templates/init-job/init-repo.yaml']:
    if nm in files:
        print('='*20, nm, '='*20)
        print(files[nm][:3000])
        print()
" 2>&1

echo "===== helm values 里 init 相关开关 ====="
kubectl get secret sh.helm.release.v1.bk-repo.v1 -n $NS -o jsonpath='{.data.release}' 2>/dev/null | base64 -d 2>/dev/null | base64 -d 2>/dev/null | python3 -c "
import sys,gzip,json,base64,yaml
raw=sys.stdin.buffer.read()
data=raw
try: data=gzip.decompress(raw)
except Exception: pass
j=json.loads(data)
v=j.get('config') or j.get('chart',{}).get('values') or {}
try:
    if isinstance(v,str): v=yaml.safe_load(v)
except Exception: pass
def walk(o,p=''):
    if isinstance(o,dict):
        for k,val in o.items():
            if re.match(r'(?i).*(init|admin|user|password).*',str(k)):
                print('  ',p+k,'=',str(val)[:80])
            walk(val,p+k+'.')
import re
walk(v)
" 2>&1
