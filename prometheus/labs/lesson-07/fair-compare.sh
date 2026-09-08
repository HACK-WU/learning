#!/usr/bin/env bash
# 同起点、同时长、同目标的 Agent vs Server 资源对照
# 目的：消除"运行时长不同"导致的磁盘/内存不公平对比
set -u
L7=/mnt/d/projects/learning/prometheus/labs/lesson-07
DUR=${1:-600}   # 默认观察 600 秒

echo "=== 清空两侧数据目录，从零开始 ==="
docker rm -f l7-agent >/dev/null 2>&1 || true
rm -rf "$L7/data-agent" 2>/dev/null
mkdir -p "$L7/data-agent"; chmod 777 "$L7/data-agent" 2>/dev/null || true

docker rm -f l7-prom >/dev/null 2>&1 || true   # server 用匿名卷，rm 即清空

T0=$(date +%s)

docker run -d --name l7-prom --network l7net -p 19100:9090 \
  -v "$L7/prometheus.yml:/etc/prometheus/prometheus.yml:ro" \
  prom/prometheus:v3.14.0 \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/prometheus \
  --storage.tsdb.retention.time=2h \
  --web.enable-lifecycle >/dev/null

docker run -d --name l7-agent --network l7net -p 19107:9090 \
  -v "$L7/agent.yml:/etc/prometheus/prometheus.yml:ro" \
  -v "$L7/data-agent:/data-agent" \
  prom/prometheus:v3.14.0 \
  --agent \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.agent.path=/data-agent \
  --web.enable-lifecycle >/dev/null

echo "  两实例已同时启动，观察 ${DUR} 秒..."
sleep "$DUR"

T1=$(date +%s)
echo "  实际观察 $((T1-T0)) 秒"

echo
echo "=== 抓取目标是否一致（序列数对齐） ==="
for c in l7-prom l7-agent; do
  n=$(curl -s "http://localhost:$([ $c = l7-prom ] && echo 19100 || echo 19107)/api/v1/targets" \
    | python -c "import sys,json;d=json.load(sys.stdin);ts=[t for t in d['data']['activeTargets'] if t.get('health')=='up'];print(len(ts))")
  echo "  $c 健康 target 数 = $n"
done

echo
echo "=== 内存 ==="
docker stats --no-stream --format "{{.Name}}|{{.MemUsage}}" l7-prom l7-agent

echo
echo "=== 磁盘 ==="
P=$(docker exec l7-prom  sh -c 'du -sk /prometheus 2>/dev/null' | cut -f1)
A=$(docker exec l7-agent sh -c 'du -sk /data-agent 2>/dev/null' | cut -f1)
echo "  server /prometheus = ${P} KB"
echo "  agent  /data-agent = ${A} KB"
if [ "$A" -gt 0 ]; then
  echo "  磁盘倍数 = $(python -c "print(f'{$P/$A:.1f}x')")  (agent 更小)"
fi

echo
echo "=== WAL 细分 ==="
docker exec l7-prom  sh -c 'du -sk /prometheus/wal /prometheus/chunks_head 2>/dev/null'
docker exec l7-agent sh -c 'du -sk /data-agent/wal 2>/dev/null'

echo
echo "=== 本地 TSDB 指标对照 ==="
for c in "l7-prom:19100" "l7-agent:19107"; do
  name=${c%%:*}; port=${c##*:}
  hs=$(docker exec $name wget -qO- http://localhost:9090/metrics 2>/dev/null | grep -E "^prometheus_tsdb_head_series" | awk '{print $2}')
  hc=$(docker exec $name wget -qO- http://localhost:9090/metrics 2>/dev/null | grep -E "^prometheus_tsdb_head_chunks" | awk '{print $2}')
  echo "  $name  head_series=${hs:-<不存在>}  head_chunks=${hc:-<不存在>}"
done
