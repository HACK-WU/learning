#!/usr/bin/env bash
set -uo pipefail
NS=blueking

echo "===== 1. bkrepo auth Pod 启动日志（找初始化痕迹）====="
AP=$(kubectl get pods -n $NS --no-headers 2>/dev/null | grep 'bkrepo-auth' | grep Running | awk '{print $1}' | head -1)
echo "  Pod: $AP"
kubectl logs $AP -n $NS --tail=60 2>&1 | grep -viE '^\s*$' | tail -25 | cut -c1-200 | sed 's/^/  /'

echo ""
echo "===== 2. 搜 auth 日志里的 admin/初始化关键字 ====="
kubectl logs $AP -n $NS 2>&1 | grep -iE 'admin|init|create.*user|默认|bootstrap' | tail -15 | cut -c1-200 | sed 's/^/  /'

echo ""
echo "===== 3. bkrepo 所有组件 Pod 状态 + 启动时间 ====="
kubectl get pods -n $NS --no-headers 2>/dev/null | grep 'bk-repo' | awk '{printf "  %-46s %-12s 重启%s\n", $1, $3, $4}'

echo ""
echo "===== 4. bkrepo 是否有 init Job（helm hook）====="
kubectl get jobs -n $NS --no-headers 2>/dev/null | grep -i 'repo' | awk '{printf "  %-46s %-10s\n", $1, $2}'
echo "  --- 所有 Pod 里找 init/initdata ---"
kubectl get pods -n $NS --no-headers 2>/dev/null | grep -iE 'repo.*init|init.*repo' | awk '{printf "  %-46s %-12s\n", $1, $3}'

echo ""
echo "===== 5. helm release 里 bk-repo 的 values（admin 初始密码配置）====="
kubectl get secret sh.helm.release.v1.bk-repo.v1 -n $NS -o jsonpath='{.data.release}' 2>/dev/null | base64 -d 2>/dev/null | base64 -d 2>/dev/null | python3 -c "
import sys,gzip,base64,json,re
raw=sys.stdin.buffer.read()
data=None
for f in [lambda: gzip.decompress(raw), lambda: raw]:
    try:
        data=f(); break
    except Exception: pass
try:
    j=json.loads(data)
    v=j.get('chart',{}).get('values',{})
    txt=v if isinstance(v,str) else json.dumps(v,indent=1)
except Exception:
    txt=data.decode('utf-8','ignore')
for line in txt.split('\n'):
    if re.search(r'(?i)(admin|initial|defaultPwd|password)', line):
        print('  ', line.strip()[:140])
" 2>&1

echo ""
echo "===== 6. bkrepo role 集合（角色表，看是否也空）====="
kubectl exec bk-mongodb-0 -n $NS -- bash -c "mongo --quiet -u root -p blueking --authenticationDatabase admin --eval 'print(\"user count=\"+db.getSiblingDB(\"bkrepo\").user.count()); print(\"role count=\"+db.getSiblingDB(\"bkrepo\").role.count()); db.getSiblingDB(\"bkrepo\").role.find().limit(5).forEach(function(r){print(JSON.stringify(r).slice(0,200))})'" 2>&1 | sed 's/^/  /'
