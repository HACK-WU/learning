#!/usr/bin/env bash
# 核验手册要引用的关键事实（精简输出）
set -uo pipefail
NS=blueking

echo "[1] Pod 总数/异常数"
echo "    total=$(kubectl get pods -n $NS --no-headers 2>/dev/null | wc -l) bad=$(kubectl get pods -n $NS --no-headers 2>/dev/null | grep -vcE 'Running|Completed')"

echo "[2] bkrepo.user 数量"
kubectl exec bk-mongodb-0 -n $NS -- bash -c "mongo --quiet -u root -p blueking --authenticationDatabase admin --eval 'print(\"    user=\"+db.getSiblingDB(\"bkrepo\").user.count()+\" role=\"+db.getSiblingDB(\"bkrepo\").role.count())'" 2>&1

echo "[3] init-mongodb Job 是否存在及状态"
kubectl get job bk-repo-bkrepo-init-mongodb -n $NS --no-headers 2>&1 | sed 's/^/    /'

echo "[4] bkapi ingress 是否存在"
kubectl get ingress bk-apigateway-bkapi -n $NS --no-headers 2>&1 | sed 's/^/    /'

echo "[5] helm release config.init 的 keys"
kubectl get secret sh.helm.release.v1.bk-repo.v1 -n $NS -o jsonpath='{.data.release}' 2>/dev/null | base64 -d 2>/dev/null | base64 -d 2>/dev/null | python3 -c "
import sys,gzip,json
raw=sys.stdin.buffer.read()
try: raw=gzip.decompress(raw)
except Exception: pass
j=json.loads(raw); cfg=j.get('config') or {}
print('    config.init keys =', list(cfg.get('init',{}).keys()))
" 2>&1

echo "[6] paas3 migrate-db Job 状态"
kubectl get job bkpaas3-apiserver-migrate-db-1 -n $NS --no-headers 2>&1 | sed 's/^/    /'

echo "[7] chart 里 init-mongodb 模板是否存在"
kubectl get secret sh.helm.release.v1.bk-repo.v1 -n $NS -o jsonpath='{.data.release}' 2>/dev/null | base64 -d 2>/dev/null | base64 -d 2>/dev/null | python3 -c "
import sys,gzip,json
raw=sys.stdin.buffer.read()
try: raw=gzip.decompress(raw)
except Exception: pass
j=json.loads(raw); ch=j.get('chart',{})
names=[f.get('name','') for f in (ch.get('templates',[]) or [])]
print('    init 相关模板 =', [n for n in names if 'init' in n.lower()])
" 2>&1
