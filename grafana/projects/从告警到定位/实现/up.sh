#!/bin/bash
# 一键启动：从告警到定位 实战项目
# 用法：bash up.sh [0|1]   参数 1 表示开启故障注入（默认 0）
set -u
FAULT="${1:-0}"
W="$(cd "$(dirname "$0")/.." && pwd)"

echo "=============================================="
echo " 启动「从告警到定位」实战项目"
echo " 故障注入: $([ "$FAULT" = "1" ] && echo '开（会触发告警）' || echo '关（正常运行）')"
echo "=============================================="

# ---- 0. 检查网络
if ! docker network inspect grafana-net >/dev/null 2>&1; then
  echo "创建网络 grafana-net ..."
  docker network create grafana-net >/dev/null
fi

# ---- 1. 被监控应用
echo "[1/5] 构建并启动 shop 应用 ..."
docker build -t p3-shop:1.1 "$W/实现/app" >/dev/null 2>&1 || {
  echo "  ❌ 镜像构建失败"; exit 1; }
docker rm -f p3-shop >/dev/null 2>&1
docker run -d --name p3-shop --network grafana-net \
  -p 9400:9400 -p 9401:9401 \
  -e SERVICE_NAME=shop-api \
  -e OTLP_ENDPOINT=http://grafana-jaeger:4318/v1/traces \
  -e LOKI_URL=http://grafana-loki:3100/loki/api/v1/push \
  -e FAULT_MODE="$FAULT" \
  -v "$W/实现/app/logs:/var/log/shop" \
  p3-shop:1.1 >/dev/null
echo "  应用 :9400(指标) :9401(健康)"

# ---- 2. Prometheus
echo "[2/5] 启动 Prometheus ..."
docker rm -f p3-prom >/dev/null 2>&1
docker run -d --name p3-prom --network grafana-net -p 3110:9090 \
  -v "$W/实现/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro" \
  prom/prometheus:v3.14.0 \
  --config.file=/etc/prometheus/prometheus.yml \
  --enable-feature=exemplar-storage >/dev/null
echo "  Prometheus :3110（已开 exemplar-storage）"

# ---- 3. Webhook
echo "[3/5] 启动告警接收器 ..."
mkdir -p "$W/实现/webhook/out"
docker rm -f p3-webhook >/dev/null 2>&1
docker run -d --name p3-webhook --network grafana-net -p 9402:8080 \
  -v "$W/实现/webhook/webhook.py:/app/webhook.py:ro" \
  -v "$W/实现/webhook/out:/out" \
  -e OUT_DIR=/out -e PORT=8080 \
  python:3.12-slim python -u /app/webhook.py >/dev/null
echo "  Webhook :9402，告警落盘到 实现/webhook/out/"

# ---- 4. 生成 dashboard
echo "[4/5] 生成 dashboard JSON ..."
(cd "$W/实现" && python3 gen_dashboard.py 2>/dev/null || uv run python gen_dashboard.py) || {
  echo "  ⚠️ dashboard 生成失败，沿用已有文件"; }

# ---- 5. Grafana
echo "[5/5] 启动 Grafana（全量 provisioning）..."
docker rm -f p3-grafana >/dev/null 2>&1
docker run -d --name p3-grafana --network grafana-net -p 3130:3000 \
  -e GF_SECURITY_ADMIN_PASSWORD=admin \
  -e GF_USERS_ALLOW_SIGN_UP=false \
  -v "$W/实现/provisioning:/etc/grafana/provisioning:ro" \
  -v "$W/dashboards:/var/lib/grafana/dashboards:ro" \
  grafana/grafana:13.2.1 >/dev/null

echo -n "  等待 Grafana 就绪"
for i in $(seq 1 45); do
  if curl -s --noproxy '*' -m 3 http://localhost:3130/api/health >/dev/null 2>&1; then
    echo " ok"; break
  fi
  echo -n "."; sleep 2
done
echo

echo "=============================================="
echo " 启动完成"
echo "   Grafana   http://localhost:3130   admin/admin"
echo "   总览盘   http://localhost:3130/d/shop-overview"
echo "   Prometheus http://localhost:3110"
echo
echo " 想触发告警？用故障模式重启应用："
echo "   bash $(basename "$0") 1"
echo " 然后等 2 分钟，查看收到告警："
echo "   docker logs p3-webhook"
echo "=============================================="
