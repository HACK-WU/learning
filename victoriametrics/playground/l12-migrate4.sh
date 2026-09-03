#!/bin/bash
# 课 12 实验 14：定位 vmctl ping 失败的根因，并修正迁移
set -u
cd /mnt/d/projects/learning/victoriametrics/playground

echo "===== [1] vmctl 帮助里 vm 相关参数 ====="
docker run --rm victoriametrics/vmctl:v1.151.0 remote-read --help 2>&1 | grep -E '^\s+--vm-' | head -20

echo ""
echo "===== [2] 探测 vminsert 各路径的 HTTP 码 ====="
for p in "/health" "/insert/555/prometheus/health" "/insert/555/prometheus/api/v1/import" "/insert/555/prometheus" "/prometheus/health" "/insert/0/prometheus/health"; do
  C=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8480$p")
  echo "  vminsert:8480$p -> HTTP $C"
done

echo ""
echo "===== [3] 对照：vmselect 的 /health ====="
for p in "/health" "/select/555/prometheus/health"; do
  C=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8481$p")
  echo "  vmselect:8481$p -> HTTP $C"
done

echo ""
echo "===== [4] 单节点 vm-learn 的 /health ====="
curl -s -o /dev/null -w "  vm-learn:8428/health -> HTTP %{http_code}\n" http://localhost:8428/health

echo ""
echo "===== [5] 方案：迁到单节点 vm-learn（有 /health，vmctl ping 能过） ====="
VM=http://localhost:8428
START=$(date -u -d '6 hours ago' +%Y-%m-%dT%H:%M:%SZ)
END=$(date -u +%Y-%m-%dT%H:%M:%SZ)
echo "时间范围: $START ~ $END"
echo "-- 迁移前：VM 里有几个 Prometheus 独有指标 --"
curl -s "$VM/api/v1/label/__name__/values" | python3 -c "import sys,json;print('  VM 指标名数 =',len(json.load(sys.stdin)['data']))"

docker run --rm --network vm-cluster-net \
  victoriametrics/vmctl:v1.151.0 \
  remote-read \
  --vm-addr=http://vm-learn:8428 \
  --vm-concurrency=4 \
  --remote-read-src-addr=http://prom-learn:9090 \
  --remote-read-filter-time-start=$START \
  --remote-read-filter-time-end=$END \
  --remote-read-step-interval=hour \
  --remote-read-concurrency=2 2>&1 | tail -25

echo ""
echo "===== [6] 迁移后核对 ====="
echo "-- VM 序列总数 --"
curl -s $VM/api/v1/series/count; echo
echo "-- VM 指标名数 --"
curl -s "$VM/api/v1/label/__name__/values" | python3 -c "import sys,json;print('  =',len(json.load(sys.stdin)['data']))"
echo "-- Prometheus 独有指标现在迁过来几个 --"
curl -s "$VM/api/v1/query?query=count(prometheus_tsdb_head_series)" \
  | python3 -c "import sys,json;r=json.load(sys.stdin)['data']['result'];print('  prometheus_tsdb_head_series =', r[0]['value'][1] if r else 'NONE')"
