#!/bin/bash
P=/mnt/d/projects/learning/victoriametrics/playground
NET=vm-cluster-net

echo "=== 1. 修复规则文件后重启 vmalert ==="
docker rm -f vmalert-learn >/dev/null 2>&1
docker run -d --name vmalert-learn --network $NET \
  -p 8880:8880 \
  -v $P/rules:/etc/vmalert:ro \
  victoriametrics/vmalert:v1.151.0 \
  -rule=/etc/vmalert/*.yml \
  -datasource.url=http://vmsel-dedup:8481/select/0/prometheus \
  -notifier.url=http://alertmanager-learn:9093 \
  -remoteWrite.url=http://vminsert-learn:8480/insert/0/prometheus \
  -remoteRead.url=http://vmsel-dedup:8481/select/0/prometheus \
  -httpListenAddr=:8880 \
  -evaluationInterval=5s >/dev/null
sleep 20
echo "  容器: $(docker ps --filter name=vmalert-learn --format '{{.Status}}')"
echo "  healthz: $(curl -s -o /dev/null -w '%{http_code}' http://localhost:8880/healthz)"
echo "  启动 fatal 检查: $(docker logs vmalert-learn 2>&1 | grep -c 'fatal')"

echo
echo "=== 2. 加载的组与规则 ==="
curl -s http://localhost:8880/api/v1/rules 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin)
for g in d['data']['groups']:
    print('  组 [%s] interval=%ss' % (g['name'], g.get('interval')))
    for r in g['rules']:
        err=r.get('lastError','')
        print('     %-24s type=%-9s err=%s' % (r.get('name'), r.get('type'), err[:65] if err else '(无)'))
" 2>/dev/null

echo
echo "=== 3. 等待规则产出（40 秒）==="
sleep 40
for m in "l11:mql:topk" "l11:mql:lag" "job:up:sum"; do
curl -s "http://localhost:8481/select/0/prometheus/api/v1/query?query=$m" 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin)
rs=d['data']['result']
if not rs: print('  %-18s (无数据)' % '$m')
for r in rs: print('  %-18s %-46s = %s' % ('$m', str(r['metric'])[:44], r['value'][1]))
" 2>/dev/null
done

echo
echo "=== 4. 验证 reload：修改规则文件后 reload 能否生效 ==="
cat > $P/rules/mql-test.yml <<'EOF'
groups:
  - name: l11-mql
    interval: 10s
    rules:
      - record: l11:mql:topk
        expr: topk_avg(1, sum by (job) (up), "job")
      - record: l11:mql:lag
        expr: lag(up{job="vmsingle"})
      - record: l11:reload:proof
        expr: 1
EOF
echo "  新增规则 l11:reload:proof（值恒为 1）"
echo "  POST /-/reload: $(curl -s -o /dev/null -w '%{http_code}' -X POST http://localhost:8880/-/reload 2>/dev/null)"
sleep 25
echo "  reload_successful: $(curl -s http://localhost:8880/metrics 2>/dev/null | grep '^vmalert_config_last_reload_successful' | grep -v '^#' | awk '{print $2}')"
curl -s "http://localhost:8481/select/0/prometheus/api/v1/query?query=l11:reload:proof" 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin)
rs=d['data']['result']
print('  l11:reload:proof ->', ('有数据: %s' % rs[0]['value'][1]) if rs else '(无数据 = reload 未生效)')
" 2>/dev/null

echo
echo "=== 5. vmagent 侧：抓取配置重载 ==="
echo "  vmagent /-/reload: $(curl -s -o /dev/null -w '%{http_code}' -X POST http://localhost:8429/-/reload 2>/dev/null)"
sleep 8
echo "  reload 后 target 数: $(curl -s http://localhost:8429/api/v1/targets 2>/dev/null | python3 -c 'import sys,json; print(len(json.load(sys.stdin)["data"]["activeTargets"]))' 2>/dev/null)"
echo "  vmagent /config 端点: $(curl -s -o /dev/null -w '%{http_code}' http://localhost:8429/config 2>/dev/null)"
