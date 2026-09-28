#!/usr/bin/env bash
set -uo pipefail

{
echo "===== 1. influxdb-proxy Pod/Service 是否存在 ====="
kubectl get pods -n blueking --no-headers 2>/dev/null | grep -i 'influxdb' | sed 's/^/  /'
kubectl get svc -n blueking --no-headers 2>/dev/null | grep -i 'influxdb' | sed 's/^/  /'

echo ""
echo "===== 2. influxdb-proxy 配置（它要连哪个 influxdb）====="
kubectl get cm bk-monitor-influxdb-proxy -n blueking -o yaml 2>/dev/null | grep -vE '^\s*#' | grep -iE 'host|port|url|backend|proxy' | head -20 | sed 's/^/  /'

echo ""
echo "===== 3. 监控元数据里 storage 表有什么 ====="
kubectl exec -n blueking deploy/bk-monitor-ingester -- env 2>/dev/null | grep -iE 'INFLUX|DB' | head -10 | sed 's/^/  /'

echo ""
echo "===== 4. 查监控 MySQL 里的 storage 记录 ====="
kubectl exec -n blueking deploy/bk-monitor-api -- python manage.py shell -c "
from metadata.models import InfluxDBProxyStorage
for s in InfluxDBProxyStorage.objects.all()[:10]:
    print('  id=',s.id,' table_id=',s.table_id,' proxy_cluster_id=',s.proxy_cluster_id)
print('count=', InfluxDBProxyStorage.objects.count())
" 2>&1 | grep -v '^Defaulted' | head -15

echo ""
echo "===== 5. migrate 日志里 influxdb proxy 相关 ====="
P=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep 'bk-monitor-migrate' | awk '{print $1}' | head -1)
[ -n "$P" ] && kubectl logs -n blueking "$P" -c on-migrate --tail=60 2>/dev/null | grep -iE 'influx|proxy|storage' | tail -15 | sed 's/^/  /'

echo ""
echo "===== 6. influxdb 是否可写（健康）====="
kubectl exec -n blueking bk-influxdb-0 -- influx -execute 'SHOW DATABASES' 2>&1 | head -10 | sed 's/^/  /'
} > /root/diag-influx.txt 2>&1
cat /root/diag-influx.txt
