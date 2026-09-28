#!/usr/bin/env bash
set -uo pipefail
NS=blueking

echo "===== 1. 提取 init.mongodb.image 与其它需要的 values ====="
kubectl get secret sh.helm.release.v1.bk-repo.v1 -n $NS -o jsonpath='{.data.release}' 2>/dev/null | base64 -d 2>/dev/null | base64 -d 2>/dev/null | python3 -c "
import sys,gzip,json,yaml
raw=sys.stdin.buffer.read()
data=raw
try: data=gzip.decompress(raw)
except Exception: pass
j=json.loads(data)
v=j.get('config') or {}
if isinstance(v,str):
    try: v=yaml.safe_load(v)
    except Exception: pass
init=v.get('init',{}) if isinstance(v,dict) else {}
print('  init.mongodb =', json.dumps(init.get('mongodb',{}),ensure_ascii=False))
print('  init.bcs.enabled =', init.get('bcs',{}).get('enabled'))
print('  auth.bcs =', json.dumps(v.get('auth',{}).get('bcs',{}),ensure_ascii=False))
print('  gateway.accessKey/secretKey =', v.get('gateway',{}).get('accessKey'), '/', str(v.get('gateway',{}).get('secretKey'))[:8]+'***')
print('  common.username/password =', v.get('common',{}).get('username'), '/', v.get('common',{}).get('password'))
print('  mongodb.enabled =', v.get('mongodb',{}).get('enabled'))
print('  global.imageRegistry =', v.get('global',{}).get('imageRegistry'))
print('  common.imageRegistry/registry =', v.get('common',{}).get('imageRegistry'), v.get('common',{}).get('registry'))
" 2>&1

echo ""
echo "===== 2. 已存在的 bkrepo 镜像（推断 registry）====="
kubectl get pods -n $NS --no-headers 2>/dev/null | grep 'bkrepo-auth' | head -1 | awk '{print "  auth Pod: "$1}'
kubectl get pod $(kubectl get pods -n $NS --no-headers 2>/dev/null | grep 'bkrepo-auth' | grep Running | awk '{print $1}' | head -1) -n $NS -o jsonpath='  image={.spec.containers[0].image}{"\n"}' 2>&1

echo ""
echo "===== 3. repository 组件的镜像（init-repo 也用得上）====="
kubectl get pod $(kubectl get pods -n $NS --no-headers 2>/dev/null | grep 'bkrepo-repository' | grep Running | awk '{print $1}' | head -1) -n $NS -o jsonpath='  image={.spec.containers[0].image}{"\n"}' 2>&1

echo ""
echo "===== 4. mongodb URI 推断（bk-repo-bkrepo-common 里的 spring data mongodb）====="
kubectl get cm bk-repo-bkrepo-common -n $NS -o yaml 2>/dev/null | grep -A3 -iE 'uri|spring' | head -20 | sed 's/^/  /'

echo ""
echo "===== 5. 检查是否已有 init-mongodb Job 残留 ====="
kubectl get jobs -n $NS --no-headers 2>/dev/null | grep -i 'init-mongo' | sed 's/^/  /'
echo "  (空=已随 hook 删除)"
