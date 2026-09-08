#!/usr/bin/env bash
set -e
D=/mnt/d/projects/learning/prometheus/labs/lesson-12
P=http://localhost:19500

echo "############################################"
echo "# 故障场景：某 target 数据断更（面板出坑）  #"
echo "############################################"

# 重启 app 让数据恢复
docker start l12-app >/dev/null 2>&1 || true
sleep 12

echo
echo "===== [症状 1] 面板出现断点 / 数据变旧 ====="
echo -n "l12_series 最新样本时间 vs 当前时间: "
curl -s "$P/api/v1/query?query=l12_series{idx=\"00000000\"}" | python3 -c "
import json,sys,time
r=json.load(sys.stdin)['data']['result']
if not r: print('empty'); raise SystemExit
ts=float(r[0]['value'][0]); now=time.time()
print(f'sample_ts={ts:.0f} now={now:.0f} 滞后={now-ts:.1f}s')"

echo
echo "===== [倒查 1] 是 target 挂了，还是 Prometheus 没抓？ ====="
echo "--- up 指标 ---"
curl -s "$P/api/v1/query?query=up{job=\"app\"}" | python3 -c "
import json,sys
for r in json.load(sys.stdin)['data']['result']:
    print('up =', r['value'][1], r['metric'])"

echo
echo "--- 最近一次抓取时长（scrape_duration_seconds） ---"
curl -s "$P/api/v1/query?query=scrape_duration_seconds{job=\"app\"}" | python3 -c "
import json,sys
for r in json.load(sys.stdin)['data']['result']:
    print(f\"{r['value'][1]}  {r['metric'].get('instance')}\")"

echo
echo "===== [倒查 2] 抓取有报错吗 ====="
curl -s "$P/api/v1/query?query=scrape_samples_scraped{job=\"app\"}" | python3 -c "
import json,sys
for r in json.load(sys.stdin)['data']['result']:
    print('samples =', r['value'][1])"

echo
echo "===== [倒查 3] 用 promtool check healthy / ready 快速定级 ====="
echo -n "healthy: "
docker run --rm --network l12net --entrypoint promtool prom/prometheus:v3.14.0 check healthy http://l12-prom:9090 2>&1
echo -n "ready:   "
docker run --rm --network l12net --entrypoint promtool prom/prometheus:v3.14.0 check ready http://l12-prom:9090 2>&1
