#!/bin/bash
GF=http://localhost:3001
AUTH="-u admin:admin"

echo "=== 1. 创建 dashboard 为何 400（看真实错误体）==="
curl -s --noproxy '*' $AUTH -X POST $GF/api/dashboards/db -H 'Content-Type: application/json' -d '{"dashboard":{"uid":"perf-diag","title":"Perf Diag","panels":[{"id":1,"type":"timeseries","title":"p1","gridPos":{"x":0,"y":0,"w":24,"h":8},"targets":[{"refId":"A","datasource":{"uid":"afx7x6dx803y8e"},"expr":"up"}]}],"schemaVersion":41},"overwrite":true}' 2>&1 | head -c 400
echo
echo

echo "=== 2. 两个 Prometheus 数据源各有多少数据 ==="
for U in afx7x6dx803y8e efxhrcfu7s3k0e; do
  echo "  --- uid=$U ---"
  curl -s --noproxy '*' $AUTH -X POST $GF/api/ds/query -H 'Content-Type: application/json' -d "{\"queries\":[{\"refId\":\"A\",\"datasource\":{\"uid\":\"$U\"},\"expr\":\"up\",\"instant\":true}],\"from\":\"now-1h\",\"to\":\"now\"}" 2>&1 | head -c 300
  echo
done
echo

echo "=== 3. 直接问 Prometheus：up 有多少序列 ==="
curl -s --noproxy '*' 'http://localhost:9090/api/v1/query?query=up' 2>&1 | head -c 200
echo
echo "  --- grafana-prom 容器 ---"
docker exec grafana-lab curl -s 'http://grafana-prom:9090/api/v1/query?query=up' 2>&1 | head -c 300
echo
echo

echo "=== 4. 实验 C 异常核查：7d 窗口到底返回什么 ==="
curl -s --noproxy '*' $AUTH -X POST $GF/api/ds/query -H 'Content-Type: application/json' -d "{\"queries\":[{\"refId\":\"A\",\"datasource\":{\"uid\":\"afx7x6dx803y8e\"},\"expr\":\"up\",\"instant\":false,\"intervalMs\":15000}],\"from\":\"now-7d\",\"to\":\"now\"}" 2>&1 | head -c 400
echo
echo

echo "=== 5. 换成有数据的指标再测窗口 ==="
for W in 1h 6h 24h; do
  SZ=$(curl -s --noproxy '*' $AUTH -X POST $GF/api/ds/query -H 'Content-Type: application/json' -d "{\"queries\":[{\"refId\":\"A\",\"datasource\":{\"uid\":\"afx7x6dx803y8e\"},\"expr\":\"node_cpu_seconds_total\",\"instant\":false,\"intervalMs\":15000}],\"from\":\"now-$W\",\"to\":\"now\"}" | wc -c)
  echo "  node_cpu_seconds_total 窗口=$W 字节=$SZ"
done
