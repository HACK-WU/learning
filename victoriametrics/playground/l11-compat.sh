#!/bin/bash
echo "=== 1. vmagent 是否支持 Prometheus 的 /api/v1/targets 兼容端点 ==="
for ep in "/api/v1/targets" "/api/v1/status/config" "/api/v1/status/flags" "/service-discovery" "/config" "/-/reload"; do
  code=$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:8429$ep" 2>/dev/null)
  printf "  %-28s -> HTTP %s\n" "$ep" "$code"
done

echo
echo "=== 2. vmalert 的 Prometheus 兼容端点 ==="
for ep in "/api/v1/rules" "/api/v1/alerts" "/api/v1/status/flags" "/-/reload" "/api/v1/rules?type=alert"; do
  code=$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:8880$ep" 2>/dev/null)
  printf "  %-28s -> HTTP %s\n" "$ep" "$code"
done

echo
echo "=== 3. 对比 Prometheus（prom-learn）的同类端点 ==="
echo "  prom-learn 状态: $(docker ps --filter name=prom-learn --format '{{.Status}}')"

echo
echo "=== 4. vmagent 支持的服务发现方式 ==="
docker exec vmagent-learn sh -c "wget -qO- http://localhost:8429/service-discovery 2>/dev/null | grep -oE '<h2[^>]*>[^<]+' | head -20" 2>/dev/null | sed 's/^/  /'

echo
echo "=== 5. 关键差异1：vmagent 的 -promscrape.config 是否支持热重载 ==="
echo "  修改配置前，target 数 = $(curl -s http://localhost:8429/api/v1/targets 2>/dev/null | python3 -c 'import sys,json; print(len(json.load(sys.stdin)["data"]["activeTargets"]))' 2>/dev/null)"
echo "  执行 /-/reload:"
echo "    HTTP $(curl -s -o /dev/null -w '%{http_code}' -X POST http://localhost:8429/-/reload 2>/dev/null)"
sleep 8
echo "  reload 后 target 数 = $(curl -s http://localhost:8429/api/v1/targets 2>/dev/null | python3 -c 'import sys,json; print(len(json.load(sys.stdin)["data"]["activeTargets"]))' 2>/dev/null)"

echo
echo "=== 6. vmalert 规则热重载 ==="
echo "  /-/reload: HTTP $(curl -s -o /dev/null -w '%{http_code}' -X POST http://localhost:8880/-/reload 2>/dev/null)"

echo
echo "=== 7. 关键差异2：MetricsQL 在 vmalert 规则中的可用性 ==="
echo "  测试 MetricsQL 特有函数在告警规则里能否用（如 lag / topk_avg）"
cat > /tmp/mql-test.yml <<'EOF'
groups:
  - name: l11-mql
    rules:
      - record: l11:mql:test
        expr: topk_avg(1, sum by (job) (up), job)
EOF
docker cp /tmp/mql-test.yml vmalert-learn:/etc/vmalert/mql-test.yml 2>/dev/null && echo "  规则文件已放入"
curl -s -X POST http://localhost:8880/-/reload >/dev/null 2>&1
sleep 20
curl -s http://localhost:8880/api/v1/rules 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin)
for g in d['data']['groups']:
    if 'mql' in g['name']:
        for r in g['rules']:
            print('  规则 %s: lastError=%s' % (r.get('name'), r.get('lastError','(无错误)')[:60]))
" 2>/dev/null
