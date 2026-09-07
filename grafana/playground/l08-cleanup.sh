#!/usr/bin/env bash
# 课 8 环境清理与确认
set -u
GF="http://localhost:3001"
AUTH="admin:admin"

echo "=========================================================="
echo " 课 8 环境清理"
echo "=========================================================="

echo ""
echo "--- [1] 清理前状态 ---"
echo -n "  告警状态: "
curl -s -u $AUTH "$GF/metrics" 2>/dev/null | grep '^grafana_alerting_alerts{' | tr '\n' ' '
echo ""

echo ""
echo "--- [2] 删除所有告警规则 ---"
curl -s -u $AUTH "$GF/api/v1/provisioning/alert-rules" | python3 -c "
import sys,json
d=json.load(sys.stdin)
print('  待删除：%d 条'%len(d))
for r in d: print('    ',r.get('uid'))
" 2>&1 | sed 's/^/  /'

for u in $(curl -s -u $AUTH "$GF/api/v1/provisioning/alert-rules" | python3 -c "
import sys,json
d=json.load(sys.stdin)
print(' '.join(r.get('uid','') for r in d))
"); do
  curl -s -u $AUTH -X DELETE "$GF/api/v1/provisioning/alert-rules/$u" -o /dev/null -w "    删除 $u -> HTTP %{http_code}\n"
done

echo ""
echo "--- [3] 删除所有 contact point ---"
for u in $(curl -s -u $AUTH "$GF/api/v1/provisioning/contact-points" | python3 -c "
import sys,json
d=json.load(sys.stdin)
print(' '.join((c.get('uid') or '') for c in d))
"); do
  curl -s -u $AUTH -X DELETE "$GF/api/v1/provisioning/contact-points/$u" -o /dev/null -w "    删除 $u -> HTTP %{http_code}\n"
done

echo ""
echo "--- [4] 删除所有静默 ---"
for id in $(curl -s -u $AUTH "$GF/api/alertmanager/grafana/api/v2/silences" | python3 -c "
import sys,json
d=json.load(sys.stdin)
print(' '.join(s.get('id','') for s in d))
"); do
  curl -s -u $AUTH -X DELETE "$GF/api/alertmanager/grafana/api/v2/silence/$id" -o /dev/null -w "    删除 ${id:0:12} -> HTTP %{http_code}\n"
done

echo ""
echo "--- [5] 删除 mute timing ---"
for u in $(curl -s -u $AUTH "$GF/api/v1/provisioning/mute-timings" | python3 -c "
import sys,json
d=json.load(sys.stdin)
print(' '.join((m.get('uid') or m.get('name') or '') for m in d))
"); do
  curl -s -u $AUTH -X DELETE "$GF/api/v1/provisioning/mute-timings/$u" -o /dev/null -w "    删除 $u -> HTTP %{http_code}\n"
done

echo ""
echo "--- [6] 恢复默认策略树 ---"
curl -s -u $AUTH -X PUT "$GF/api/v1/provisioning/policies" \
  -H 'Content-Type: application/json' \
  -d '{"receiver":"empty","group_by":["grafana_folder","alertname"]}' \
  -o /dev/null -w "    HTTP %{http_code}\n"

echo ""
echo "--- [7] 等待状态归零（最多 180 秒）---"
for i in $(seq 1 36); do
  sleep 5
  S=$(curl -s -u $AUTH "$GF/metrics" 2>/dev/null | grep '^grafana_alerting_alerts{' | awk '{s+=$2} END {print s+0}')
  if [ "$S" = "0" ]; then
    echo "    t=$((i*5))s 状态已归零 ✅"
    break
  fi
  if [ $((i % 4)) -eq 0 ]; then
    echo "    t=$((i*5))s 剩余状态总数=$S"
  fi
done

echo ""
echo "--- [8] 清理后确认 ---"
echo -n "  告警状态: "
curl -s -u $AUTH "$GF/metrics" 2>/dev/null | grep '^grafana_alerting_alerts{' | tr '\n' ' '
echo ""
echo -n "  规则数: "
curl -s -u $AUTH "$GF/api/v1/provisioning/alert-rules" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))"
echo -n "  contact point 数: "
curl -s -u $AUTH "$GF/api/v1/provisioning/contact-points" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))"
echo -n "  mute timing 数: "
curl -s -u $AUTH "$GF/api/v1/provisioning/mute-timings" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))"
echo -n "  静默数(含expired历史): "
curl -s -u $AUTH "$GF/api/alertmanager/grafana/api/v2/silences" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))"
echo -n "  策略树: "
curl -s -u $AUTH "$GF/api/v1/provisioning/policies" | python3 -c "import sys,json; print(json.dumps(json.load(sys.stdin),ensure_ascii=False))"

echo ""
echo "--- [9] 容器状态 ---"
docker ps --format '{{.Names}} {{.Status}}' | grep -E 'grafana-lab|grafana-prom|grafana-node|l08-webhook' | sed 's/^/  /'

echo ""
echo "--- [10] Prometheus targets ---"
curl -s http://localhost:9201/api/v1/targets | python3 -c "
import sys,json
d=json.load(sys.stdin)
ts=d.get('data',{}).get('activeTargets') or []
print('  target 数：%d'%len(ts))
for t in ts: print('    %-20s health=%s'%(t.get('scrapePool'),t.get('health')))
"

echo ""
echo "=========================================================="
echo " 清理完成"
echo "=========================================================="
