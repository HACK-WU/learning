#!/bin/bash
# 课 12 实验 28：排查「写入 204 却查不到」—— retention 时间窗问题
set -u
cd /mnt/d/projects/learning/victoriametrics/playground
VM=http://localhost:8428

echo "===== [1] 时间同步性检查 ====="
echo "-- 宿主机(WSL) 时间 --"
date
date +%s
echo "-- 容器时间 --"
docker exec vm-learn date
docker exec vm-learn date +%s
echo "-- 差值（秒） --"
H=$(date +%s)
C=$(docker exec vm-learn date +%s)
echo "  宿主机 - 容器 = $((H-C))"

echo ""
echo "===== [2] 用容器时间重写入并立即查询 ====="
CTS=$(docker exec vm-learn date +%s)
echo "  用容器时间戳 = $CTS"
curl -s -o /dev/null -w "  写入 HTTP=%{http_code}\n" -X POST \
  --data-binary "l12_cts_test{job=\"l12\"} 555 ${CTS}000" "$VM/api/v1/import/prometheus"
sleep 2
echo "-- 立即查 --"
curl -s --data-urlencode 'query=l12_cts_test' "$VM/api/v1/query" | head -c 250; echo
echo "-- 用 time 参数精确查（time=容器时间） --"
curl -s --data-urlencode 'query=l12_cts_test' --data-urlencode "time=$CTS" "$VM/api/v1/query" | head -c 250; echo

echo ""
echo "===== [3] 用不带时间戳的写入（当前时间） ====="
curl -s -o /dev/null -w "  写入 HTTP=%{http_code}\n" -X POST \
  --data-binary 'l12_notime_test{job="l12"} 777' "$VM/api/v1/import/prometheus"
sleep 2
curl -s --data-urlencode 'query=l12_notime_test' "$VM/api/v1/query" | head -c 250; echo

echo ""
echo "===== [4] 检查 retentionPeriod 与数据时间范围 ====="
echo "-- 容器启动参数 --"
docker inspect vm-learn --format '{{range .Args}}{{.}}{{"\n"}}{{end}}' | grep -iE "retention" 
echo "-- 查 vm_app_uptime_seconds 与最早数据时间 --"
curl -s "$VM/api/v1/query?query=vm_app_uptime_seconds" | head -c 200; echo
echo "-- 查当前数据的最大时间戳（用 vm_rows 或 自监控） --"
curl -s "$VM/api/v1/query?query=vm_data_size_bytes" | head -c 200; echo

echo ""
echo "===== [5] 关键：查一个已知长期存在的指标，看数据时间范围 ====="
curl -s --data-urlencode 'query=up' --data-urlencode "time=$(date +%s)" "$VM/api/v1/query" \
  | python3 -c "
import sys,json,datetime
r=json.load(sys.stdin)['data']['result']
print('   up 序列数 =', len(r))
for x in r[:3]:
    ts=int(float(x['value'][0]))
    print('   ', x['metric'].get('job'), 'ts =', ts, datetime.datetime.fromtimestamp(ts).strftime('%Y-%m-%d %H:%M:%S'))
" 2>&1 | head -6

echo ""
echo "===== [6] 结论验证：用「现在」这个时间点写入的数据，是否能稳定查到 ====="
NOW=$(date +%s)
curl -s -o /dev/null -X POST --data-binary "l12_now_test{job=\"l12\"} 999 ${NOW}000" "$VM/api/v1/import/prometheus"
sleep 2
curl -s --data-urlencode 'query=l12_now_test' "$VM/api/v1/query" | head -c 250; echo
echo "-- 再等 5 秒查一次 --"
sleep 5
curl -s --data-urlencode 'query=l12_now_test' "$VM/api/v1/query" | head -c 250; echo
