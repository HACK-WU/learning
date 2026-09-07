#!/usr/bin/env bash
# 验证修复后的 gf_ready 判据：对现有 3001 应返回 true
# 只做判定，不重建容器（避免打断正在跑的实验环境）
set -u
GF_PORT=3001
PROM_PORT=9201
NE_PORT=9101

gf_ready_new() {
  curl -s "http://localhost:${GF_PORT}/api/health" 2>/dev/null \
    | tr -d ' \n' | grep -q '"database":"ok"'
}
gf_ready_old() {
  curl -s "http://localhost:${GF_PORT}/api/health" 2>/dev/null | grep -q '"database":"ok"'
}
prom_ready() {
  [ "$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:${PROM_PORT}/-/ready" 2>/dev/null)" = "200" ] \
  && curl -s "http://localhost:${PROM_PORT}/api/v1/query?query=up" 2>/dev/null | grep -q '"status":"success"'
}
ne_ready() {
  curl -s "http://localhost:${NE_PORT}/metrics" 2>/dev/null | grep -q 'node_cpu_seconds_total'
}

echo "=== 修复前后对照（对已在运行的 3001）==="
echo -n "  旧判据（紧凑 grep）    : "; gf_ready_old && echo "✅ 就绪" || echo "❌ 判未就绪"
echo -n "  新判据（tr 压平+紧凑） : "; gf_ready_new && echo "✅ 就绪" || echo "❌ 判未就绪"
echo
echo "=== 新判据下三组件整体状态 ==="
echo -n "  Grafana    : "; gf_ready_new && echo "✅" || echo "❌"
echo -n "  Prometheus : "; prom_ready && echo "✅" || echo "❌"
echo -n "  node-expo  : "; ne_ready && echo "✅" || echo "❌"
echo
echo "=== 期望：新判据三项全 ✅（旧判据 Grafana 必为 ❌，这正是要修的 bug）==="
