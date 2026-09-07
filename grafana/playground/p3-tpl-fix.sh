#!/bin/bash
set -u
W=/mnt/d/projects/learning/grafana/projects/从告警到定位
echo "=== 1. 清空旧告警文件，便于区分 ==="
rm -f "$W/实现/webhook/out/"*.json 2>/dev/null
echo "  已清空"
echo

echo "=== 2. 重启 Grafana 重载告警规则（模板改动需重载）==="
docker restart p3-grafana >/dev/null 2>&1
for i in $(seq 1 45); do
  R=$(curl -s --noproxy '*' -m 3 http://localhost:3130/api/health | tr -d ' \n')
  if [ -n "$R" ]; then echo "  ${i}x2s ready"; break; fi
  sleep 2
done
echo

echo "=== 3. 确认新模板已生效 ==="
curl -s --noproxy '*' -u admin:admin http://localhost:3130/api/v1/provisioning/alert-rules/shop-p90-latency 2>&1 | python3 -c "
import sys,json
d=json.load(sys.stdin)
print('  summary:', d.get('annotations',{}).get('summary'))
" 2>&1
echo

echo "=== 4. 等 110 秒让告警重新触发 ==="
sleep 110
echo "  done"
echo

echo "=== 5. 新收到的告警（模板渲染了吗）==="
docker logs p3-webhook 2>&1 | tail -30
echo

echo "=== 6. 落盘文件核对 ==="
ls "$W/实现/webhook/out/" 2>&1 | head
