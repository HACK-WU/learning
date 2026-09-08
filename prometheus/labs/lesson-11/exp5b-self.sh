#!/usr/bin/env bash
set -e
D=/mnt/d/projects/learning/prometheus/labs/lesson-11
NET=l11cnet; PORT=19455
docker rm -f l11c-self >/dev/null 2>&1 || true
docker run -d --name l11c-self --network $NET -p $PORT:9090 \
  -v $D/prometheus-self.yml:/etc/prometheus/prometheus.yml:ro \
  prom/prometheus:v3.14.0 \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/prometheus \
  --web.enable-lifecycle --web.enable-admin-api >/dev/null
for i in $(seq 1 60); do curl -sf "http://localhost:$PORT/-/ready" >/dev/null 2>&1 && break; sleep 1; done
sleep 40
echo "=== 加上 self-scrape 后的指标总数 ==="
curl -s "http://localhost:$PORT/api/v1/label/__name__/values" | python3 -c "
import sys,json
d=json.load(sys.stdin)['data']
print(f'  共 {len(d)} 个指标')
"
echo ""
echo "=== 关键自身指标可用性 ==="
curl -s "http://localhost:$PORT/api/v1/label/__name__/values" | python3 -c "
import sys,json
d=set(json.load(sys.stdin)['data'])
checks = {
 'prometheus_tsdb_head_series':'序列数（基数监控核心）',
 'process_resident_memory_bytes':'进程内存（容量监控核心）',
 'prometheus_engine_query_duration_seconds':'查询耗时',
 'prometheus_scrape_pool_targets':'target 数',
 'prometheus_target_scrapes_exceeded_sample_limit_total':'超限次数',
 'prometheus_target_scrapes_sample_duplicate_timestamp_total':'重复时间戳',
 'promhttp_metric_handler_requests_total':'HTTP 请求',
 'go_memstats_heap_inuse_bytes':'Go 堆',
 'prometheus_tsdb_compactions_total':'compaction',
 'prometheus_rule_evaluation_duration_seconds':'规则评估',
 'prometheus_tsdb_wal_fsync_duration_seconds':'WAL fsync',
 'prometheus_tsdb_head_truncations_total':'head 截断',
}
for k,v in checks.items():
    print(f\"  {'✅' if k in d else '❌'} {k:<58} {v}\")
"
