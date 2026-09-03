#!/usr/bin/env bash
# 课 4 环境检查：容器状态、数据残留、镜像可用性、端口占用
set -u
OUT=/tmp/l4_env.txt
: > "$OUT"

{
echo "===== 1. 容器状态 ====="
docker ps -a --filter name=vm-learn --format '  {{.Names}} | {{.Status}} | {{.Ports}}'

echo
echo "===== 2. 健康与已有数据 ====="
echo "  health: $(curl -s -m 5 http://localhost:8428/health)"
echo "  series/count: $(curl -s -m 10 http://localhost:8428/api/v1/series/count)"

echo
echo "===== 3. 课3 遗留指标是否还在 ====="
for m in l3_counter_total l3_gappy l3_mem_bytes l3_clean_counter; do
  n=$(curl -s -m 10 -G http://localhost:8428/api/v1/series \
      --data-urlencode "match[]=${m}" | python3 -c 'import sys,json;print(len(json.load(sys.stdin)["data"]))' 2>/dev/null)
  echo "  ${m}: ${n} 条"
done

echo
echo "===== 4. 本地已有镜像 ====="
docker images --format '  {{.Repository}}:{{.Tag}}' | grep -Ei 'prom|victoria|vmagent|graphite' || echo "  (无 prom/victoria 相关镜像)"

echo
echo "===== 5. VM 版本 ====="
curl -s -m 10 http://localhost:8428/api/v1/status/tsdb \
  | python3 -c 'import sys,json;d=json.load(sys.stdin)["data"];print("  head series:",d.get("headSeries"));print("  total series:",d.get("totalSeries"))' 2>/dev/null
curl -s -m 10 http://localhost:8428/ | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -3

echo
echo "===== 6. Docker 网络与镜像拉取能力 ====="
timeout 25 docker pull prom/prometheus:v2.53.0 >/dev/null 2>&1 \
  && echo "  prom/prometheus 拉取成功" \
  || echo "  prom/prometheus 拉取失败或超时（需检查网络/镜像源）"

echo
echo "===== 7. 端口占用情况 ====="
for p in 8428 8429 9090 9091 2003 4242; do
  if (echo > /dev/tcp/127.0.0.1/$p) 2>/dev/null; then echo "  $p: 已占用"
  else echo "  $p: 空闲"; fi
done
} > "$OUT" 2>&1

cat "$OUT"
