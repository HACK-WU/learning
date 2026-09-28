#!/usr/bin/env bash
set -uo pipefail
NS=blueking

echo "===== 1. chart 默认 values.yaml 里的 init 段 ====="
kubectl get secret sh.helm.release.v1.bk-repo.v1 -n $NS -o jsonpath='{.data.release}' 2>/dev/null | base64 -d 2>/dev/null | base64 -d 2>/dev/null | python3 -c "
import sys,gzip,json,base64,re,yaml
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
# values.yaml 可能在 files 里
for nm in files:
    if nm.endswith('values.yaml') or nm=='values.yaml':
        print('  找到:',nm)
        txt=files[nm]
        m=re.search(r'^init:\s*\n((?:[ \t]+.*\n|\n)*?)(?=^\S)', txt, re.M)
        print('  --- init 段 ---')
        print('\n'.join('    '+l for l in (m.group(1).split('\n') if m else [])[:60]))
        break
else:
    print('  files 中无 values.yaml，列出所有 files key:')
    print('   ', [k for k in files][:20])
" 2>&1

echo ""
echo "===== 2. 集群内是否已有 init-mongodb 相关镜像（查所有 bkrepo Pod 的 image 去重）====="
kubectl get pods -n $NS -o jsonpath='{range .items[*]}{range .spec.containers[*]}{.image}{"\n"}{end}{end}' 2>/dev/null | sort -u | sed 's/^/  /'

echo ""
echo "===== 3. 确认 init-mongodb.enabled 的实际判定（chart config 里到底有没有）====="
kubectl get secret sh.helm.release.v1.bk-repo.v1 -n $NS -o jsonpath='{.data.release}' 2>/dev/null | base64 -d 2>/dev/null | base64 -d 2>/dev/null | python3 -c "
import sys,gzip,json
raw=sys.stdin.buffer.read()
data=raw
try: data=gzip.decompress(raw)
except Exception: pass
j=json.loads(data)
cfg=j.get('config') or {}
print('  config.init keys =', list(cfg.get('init',{}).keys()) if isinstance(cfg.get('init'),dict) else cfg.get('init'))
print('  config.init.mongodb =', cfg.get('init',{}).get('mongodb','<不存在>') if isinstance(cfg.get('init'),dict) else '?')
" 2>&1

echo ""
echo "===== 4. 对比：其它 release（如 bkpaas3）的 init Job 是怎么建用户的 ====="
kubectl get jobs -n $NS --no-headers 2>/dev/null | awk '{printf "  %-50s %s\n", $1, $2}' | grep -iE 'init|mongo' | sed 's/^/  /'
