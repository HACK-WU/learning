#!/usr/bin/env bash
set -uo pipefail
NS=blueking

echo "===== 1. bkrepo helm release 的 values（找初始 admin 密码）====="
kubectl get secret sh.helm.release.v1.bk-repo.v1 -n $NS -o jsonpath='{.data.release}' 2>/dev/null | base64 -d | base64 -d 2>/dev/null | python3 -c "
import sys,json,base64,gzip,io
raw=sys.stdin.buffer.read()
try:
    d=json.loads(raw)
    s=base64.b64decode(d['chart']['values'] if 'chart' in d else '') if 'chart' in d else b''
except Exception as e:
    s=b''
# 尝试解压 gzip
try:
    s=gzip.decompress(raw)
except Exception:
    pass
import re
txt=s.decode('utf-8','ignore') if s else raw.decode('utf-8','ignore')
for m in re.findall(r'(?i)(admin|password|passwd|pwd|secret)[^\n]{0,80}', txt):
    print('  ', m[:110])
" 2>&1 | head -25

echo ""
echo "===== 2. bkrepo auth 组件的 ConfigMap ====="
for cm in $(kubectl get cm -n $NS -o name 2>/dev/null | grep -i 'bkrepo\|repo-'); do
  echo "  --- $cm ---"
  kubectl get $cm -n $NS -o yaml 2>/dev/null | grep -iE 'admin|password|init' | head -6 | sed 's/^/    /'
done

echo ""
echo "===== 3. bkrepo auth Pod 的环境变量全量（含密码）====="
AP=$(kubectl get pods -n $NS --no-headers 2>/dev/null | grep 'bkrepo-auth' | grep Running | awk '{print $1}' | head -1)
echo "  Pod: $AP"
kubectl exec $AP -n $NS -- env 2>/dev/null | grep -iE 'ADMIN|PASS|USER|INIT' | head -10 | sed 's/^/    /'

echo ""
echo "===== 4. bkrepo 数据库里的用户（如果有 mongodb/mysql 直连）====="
kubectl get svc -n $NS --no-headers 2>/dev/null | grep -iE 'bkrepo|mongo|mysql' | awk '{printf "  %-30s %s\n", $1, $5}'

echo ""
echo "===== 5. 关键：bkrepo 是否有初始化 Job 设置过密码 ====="
kubectl get jobs -n $NS --no-headers 2>/dev/null | grep -i bkrepo | awk '{printf "  %-46s %-10s\n", $1, $2}'

echo ""
echo "===== 6. 看 bkrepo gateway 的认证配置（auth 服务地址）====="
kubectl get cm bk-repo-bkrepo-gateway-config -n $NS -o yaml 2>/dev/null | grep -iE 'auth|admin' | head -8 | sed 's/^/    /'
