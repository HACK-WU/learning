#!/bin/bash
P=/mnt/d/projects/learning/victoriametrics/playground

echo "=== 1. MetricsQL 在 vmalert 记录规则中是否可用 ==="
sleep 10
curl -s http://localhost:8880/api/v1/rules 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin)
for g in d['data']['groups']:
    print('  组 [%s] 文件=%s' % (g['name'], g.get('file','').split('/')[-1]))
    for r in g['rules']:
        err=r.get('lastError','')
        print('     %-26s type=%-9s lastError=%s' % (r.get('name'), r.get('type'), err[:70] if err else '(无)'))
" 2>/dev/null

echo
echo "  --- 验证 l11:mql:test 是否产出数据 ---"
curl -s "http://localhost:8481/select/0/prometheus/api/v1/query?query=l11:mql:test" 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin)
rs=d['data']['result']
print('     ', '有数据: %s' % [(r['metric'].get('job'), r['value'][1]) for r in rs] if rs else '(无数据)')
" 2>/dev/null

echo
echo "=== 2. 兼容性缺口：/api/v1/status/flags 差异 ==="
echo "  vmagent :8429 -> $(curl -s -o /dev/null -w '%{http_code}' http://localhost:8429/api/v1/status/flags)"
echo "  vmalert :8880 -> $(curl -s -o /dev/null -w '%{http_code}' http://localhost:8880/api/v1/status/flags)"
echo "  (Prometheus 正常返回 200，这里 400 = 不兼容点)"

echo
echo "=== 3. vmagent 的关键能力：流式聚合（stream aggregation）==="
echo "  vmagent 支持 -remoteWrite.streamAggr.config 在采集端预聚合"
cat > $P/stream-aggr.yml <<'EOF'
- match: '{__name__=~"up"}'
  interval: 30s
  outputs: [total]
EOF
echo "  配置文件已写入"

echo
echo "=== 4. vmagent 的基数限制能力 ==="
echo "  --- 关键 flag 是否存在 ---"
docker exec vmagent-learn sh -c "/vmagent-prod --help 2>&1 | grep -iE 'maxScrapeSize|samplesPerScrape|seriesLimit|streamAggr' | head -10" 2>/dev/null | sed 's/^/  /'

echo
echo "=== 5. vmagent 队列上限保护：超过 maxDiskUsagePerURL 会怎样 ==="
curl -s http://localhost:8429/metrics 2>/dev/null | grep -E "^vmagent_remotewrite_max_disk_usage|^vmagent_remotewrite_pending_data_bytes" | grep -v "^#" | sed 's/^/  /'

echo
echo "=== 6. 对比：Prometheus 的 remote_write 队列 vs vmagent ==="
echo "  prom-learn 的 queue_config:"
docker exec prom-learn sh -c "cat /etc/prometheus/prometheus.yml 2>/dev/null | grep -A6 'queue_config' | head -12" 2>/dev/null | sed 's/^/  /'
echo "  (Prometheus 队列在内存，容量按样本数；vmagent 在磁盘，容量按字节)"
