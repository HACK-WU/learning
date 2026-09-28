#!/usr/bin/env bash
set -uo pipefail
NS=blueking

echo "===== 1. 起长期探针 Pod（完整 envFrom，和 Job 一样）====="
BAK=$(ls -d /root/bk72/install/bk-job-backup-* 2>/dev/null | tail -1)
python3 - "$BAK/bkpaas3-apiserver-migrate-db-1.yaml" <<'PY'
import json,sys,yaml
d = yaml.safe_load(open(sys.argv[1]))
c = d['spec']['template']['spec']['containers'][0]
pod = {
 "apiVersion":"v1","kind":"Pod",
 "metadata":{"name":"paas3-mig-probe","namespace":"blueking"},
 "spec":{"restartPolicy":"Never","containers":[{
    "name":"mig","image":c['image'],
    "command":["sleep","1800"],
    "envFrom":c.get('envFrom') or [],
    "env": (c.get('env') or []) + [{"name":"PAAS_BK_IAM_USE_APIGATEWAY","value":"false"}],
    "volumeMounts":c.get('volumeMounts') or [],
 }],"volumes":d['spec']['template']['spec'].get('volumes') or []}
}
json.dump(pod, open('/tmp/probe2.json','w'))
print("  已生成 /tmp/probe2.json")
PY
kubectl delete pod paas3-mig-probe -n $NS --wait=false 2>/dev/null >/dev/null
kubectl apply -f /tmp/probe2.json 2>&1 | sed 's/^/  /'

for i in $(seq 1 24); do
  S=$(kubectl get pod paas3-mig-probe -n $NS -o jsonpath='{.status.phase}' 2>/dev/null)
  [ "$S" = "Running" ] && { echo "  Running"; break; }
  sleep 5
done

echo ""
echo "===== 2. 探针里的实际 IAM 配置 ====="
kubectl exec paas3-mig-probe -n $NS -- bash -c 'cd /app && python -c "
import django, os
os.environ.setdefault(\"DJANGO_SETTINGS_MODULE\",\"paasng.settings\")
django.setup()
from django.conf import settings
print(\"  USE_APIGATEWAY =\", getattr(settings,\"BK_IAM_USE_APIGATEWAY\",None))
print(\"  APIGATEWAY_URL =\", getattr(settings,\"BK_IAM_APIGATEWAY_URL\",None))
print(\"  V3_INNER_URL   =\", settings.BK_IAM_V3_INNER_URL)
" 2>&1 | grep -viE "warning|deprecat|_jws|INFO"' 2>&1 | sed 's/^/    /'

echo ""
echo "===== 3. 手动跑 migrate，完整输出 ====="
kubectl exec paas3-mig-probe -n $NS -- bash -c 'cd /app && python manage.py migrate --no-input 2>&1 | grep -viE "InsecureKeyLength|Deprecation|warnings.warn" | tail -22' 2>&1 | sed 's/^/    /'

echo ""
echo "===== 4. 关键：bkiam-api 的 IAM 迁移 API 是否可用 ===="
echo "  ingress bkiam-api -> 指向哪个 svc（前面看到 bkiam-web）"
kubectl get ingress bkiam -n $NS -o jsonpath='{range .spec.rules[*]}{"    host="}{.host}{" -> svc="}{.http.paths[0].backend.service.name}{"\n"}{end}' 2>&1
echo ""
echo "  IAM 后端 API 应该在 bkiam-saas-api 还是独立 bkiam backend？"
kubectl get svc -n $NS --no-headers 2>/dev/null | grep -i 'bkiam' | awk '{printf "    %-30s %s\n", $1, $5}'
echo ""
echo "  测各 svc 的 IAM 迁移端点:"
for s in bkiam-web bkiam-saas-api; do
  C=$(kubectl exec paas3-mig-probe -n $NS -- bash -c "curl -s -o /dev/null -w '%{http_code}' --max-time 8 http://$s.blueking.svc.cluster.local/api/v1/model/system/" 2>/dev/null)
  echo "    $s /api/v1/model/system/ -> ${C:-000}"
done
