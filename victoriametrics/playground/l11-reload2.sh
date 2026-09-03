#!/bin/bash
echo "=== 1. vmalert reload 失败原因 ==="
echo "  --- 重启后状态 ---"
echo "  vmalert 容器: $(docker ps --filter name=vmalert-learn --format '{{.Status}}')"
echo "  healthz: $(curl -s -o /dev/null -w '%{http_code}' http://localhost:8880/healthz)"
echo "  reload_successful: $(curl -s http://localhost:8880/metrics 2>/dev/null | grep '^vmalert_config_last_reload_successful' | grep -v '^#' | awk '{print $2}')"

echo
echo "  --- 重启后加载的组 ---"
curl -s http://localhost:8880/api/v1/rules 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin)
for g in d['data']['groups']:
    print('    组 [%s] 规则数=%d' % (g['name'], len(g['rules'])))
    for r in g['rules']:
        err=r.get('lastError','')
        print('       %-24s type=%-9s err=%s' % (r.get('name'), r.get('type'), err[:70] if err else '(无)'))
" 2>/dev/null

echo
echo "  --- vmalert 日志尾部 ---"
docker logs vmalert-learn 2>&1 | tail -20 | sed 's/^/    /'

echo
echo "=== 2. reload 端点排查 ==="
echo "  GET  /-/reload : $(curl -s -o /dev/null -w '%{http_code}' http://localhost:8880/-/reload)"
echo "  POST /-/reload : $(curl -s -o /dev/null -w '%{http_code}' -X POST http://localhost:8880/-/reload)"
echo "  带 reloadAuthKey? 检查启动 flags:"
docker exec vmalert-learn sh -c "cat /proc/1/cmdline 2>/dev/null | tr '\0' '\n'" | sed 's/^/    /'

echo
echo "=== 3. MetricsQL 规则现在是否生效 ==="
sleep 25
for m in "l11:mql:topk" "l11:mql:lagtest"; do
curl -s "http://localhost:8481/select/0/prometheus/api/v1/query?query=$m" 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin)
rs=d['data']['result']
if not rs: print('     $m : (无数据)')
for r in rs: print('     $m : %s = %s' % (r['metric'], r['value'][1]))
" 2>/dev/null
done

echo
echo "=== 4. 直接验证 MetricsQL 函数在查询侧可用（排除规则侧问题）==="
echo "  --- topk_avg 在 vmselect 上直接查 ---"
curl -s "http://localhost:8481/select/0/prometheus/api/v1/query?query=topk_avg(1,%20sum%20by%20(job)%20(up),%20job)" 2>/dev/null | head -c 300
echo
echo "  --- lag 在 vmselect 上直接查 ---"
curl -s "http://localhost:8481/select/0/prometheus/api/v1/query?query=lag(up)" 2>/dev/null | head -c 300
echo

echo
echo "=== 5. Prometheus 侧对照：同样函数在 prom-learn 上 ==="
echo "  --- topk_avg 在 Prometheus 上 ---"
curl -s "http://localhost:9090/api/v1/query?query=topk_avg(1,%20sum%20by%20(job)%20(up),%20job)" 2>/dev/null | head -c 250
echo
echo "  --- lag 在 Prometheus 上 ---"
curl -s "http://localhost:9090/api/v1/query?query=lag(up)" 2>/dev/null | head -c 250
echo
