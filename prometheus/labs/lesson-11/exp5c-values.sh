#!/usr/bin/env bash
PORT=19455
q(){ curl -s --data-urlencode "query=$1" "http://localhost:$PORT/api/v1/query" | python3 -c "
import sys,json
d=json.load(sys.stdin)
if d['status']!='success': print('  ERR',d.get('error')); sys.exit()
r=d['data']['result']
if not r: print('  (empty)'); sys.exit()
for x in r[:3]:
    m=x['metric']; lab=','.join(f'{k}={v}' for k,v in m.items() if k not in ('__name__',))
    print(f\"  {m.get('__name__')}{'{'+lab+'}' if lab else ''} = {x['value'][1]}\")
"; }

echo "===== 必看自身指标实测值 ====="
echo ""
echo "【1. 基数 / 容量】"
echo "prometheus_tsdb_head_series:"; q 'prometheus_tsdb_head_series'
echo "process_resident_memory_bytes:"; q 'process_resident_memory_bytes / 1024 / 1024'
echo "go_memstats_heap_inuse_bytes:"; q 'go_memstats_heap_inuse_bytes / 1024 / 1024'
echo ""
echo "【2. 抓取健康】"
echo "up:"; q 'up'
echo "scrape_duration_seconds:"; q 'scrape_duration_seconds'
echo "scrape_samples_scraped:"; q 'scrape_samples_scraped'
echo ""
echo "【3. 写入 / 存储】"
echo "prometheus_tsdb_wal_fsync_duration_seconds (p99):"; q 'histogram_quantile(0.99, rate(prometheus_tsdb_wal_fsync_duration_seconds_bucket[5m]))'
echo "rate(prometheus_tsdb_head_series_appended_total):"; q 'rate(prometheus_tsdb_head_series_appended_total[5m])'
echo ""
echo "【4. 查询】"
echo "prometheus_engine_query_duration_seconds (p99):"; q 'histogram_quantile(0.99, rate(prometheus_engine_query_duration_seconds_bucket[5m]))'
echo ""
echo "===== 超限类指标（基数治理直接相关）====="
q 'prometheus_target_scrapes_exceeded_sample_limit_total'
q 'prometheus_target_scrapes_sample_duplicate_timestamp_total'
