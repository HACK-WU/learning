#!/usr/bin/env bash
D=/mnt/d/projects/learning/prometheus/labs/lesson-12
P=http://localhost:19500

echo "===== 重启前 ====="
echo -n "l12_series count: "
curl -s "$P/api/v1/query?query=count(l12_series)" | python3 -c "
import json,sys; r=json.load(sys.stdin)['data']['result']
print(r[0]['value'][1] if r else 'empty')"
echo -n "headSeries: "
curl -s $P/api/v1/status/tsdb | python3 -c "import json,sys; print(json.load(sys.stdin)['data']['headStats']['numSeries'])"

echo
echo "===== 重启 Prometheus（模拟运维重启） ====="
docker restart l12-prom >/dev/null
for i in $(seq 1 40); do
  if curl -sf $P/-/ready >/dev/null 2>&1; then echo "ready after ${i}s"; break; fi
  sleep 1
done

sleep 5
echo
echo "===== 重启后：删除的数据复活了吗？ ====="
echo -n "l12_series count: "
curl -s "$P/api/v1/query?query=count(l12_series)" | python3 -c "
import json,sys; r=json.load(sys.stdin)['data']['result']
print(r[0]['value'][1] if r else 'empty')"
echo -n "headSeries: "
curl -s $P/api/v1/status/tsdb | python3 -c "import json,sys; print(json.load(sys.stdin)['data']['headStats']['numSeries'])"

echo
echo "===== 结论判定 ====="
echo "若 count 为空 → tombstone 已写入 WAL，重启不复活（删除持久化成功）"
echo "若 count=20000  → head 中的删除随重启丢失，数据复活"
