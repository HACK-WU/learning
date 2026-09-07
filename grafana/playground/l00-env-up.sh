#!/usr/bin/env bash
# 起 Grafana 课程实验环境：Grafana + Prometheus + node-exporter
# 端口：Grafana 3001 / Prometheus 9091 / node-exporter 9101
set -u
NET=grafana-net
GF_PORT=3001
# ⚠️ 9091 已被 Prometheus 课程遗留的 pushgateway 占用（2026-09-04 实测冲突）
#    且 pushgateway 对 /-/ready 也返回 200，导致"只看 HTTP 码"的探测假成功。
#    故改用 9201，并把判据升级为"验证应答身份"而非只看状态码。
PROM_PORT=9201
NE_PORT=9101

echo "=== 1. 建网络（已存在则跳过）==="
docker network create $NET 2>/dev/null || echo "  网络 $NET 已存在"

echo "=== 2. 起 node-exporter ==="
docker rm -f grafana-node >/dev/null 2>&1
docker run -d --name grafana-node --network $NET -p ${NE_PORT}:9100 \
  prom/node-exporter:v1.10.2 >/dev/null
echo "  node-exporter -> 宿主 $NE_PORT"

echo "=== 3. 起 Prometheus ==="
docker rm -f grafana-prom >/dev/null 2>&1
docker run -d --name grafana-prom --network $NET -p ${PROM_PORT}:9090 \
  -v /mnt/d/projects/learning/grafana/playground/prometheus.yml:/etc/prometheus/prometheus.yml:ro \
  prom/prometheus:v3.14.0 >/dev/null
echo "  Prometheus -> 宿主 $PROM_PORT"

echo "=== 4. 起 Grafana ==="
docker rm -f grafana-lab >/dev/null 2>&1
docker run -d --name grafana-lab --network $NET -p ${GF_PORT}:3000 \
  grafana/grafana:13.2.1 >/dev/null
echo "  Grafana -> 宿主 $GF_PORT"

echo "=== 5. 等就绪（最多 180 秒 = 90 次 × 2s）==="
# 判据不是「HTTP 200」，而是「应答者确实是它自己」——
# 2026-09-04 踩坑：9091 上跑的是 pushgateway，对 /-/ready 同样返回 200，
# 只看状态码会判成「Prometheus 已就绪」，后面全线跑空。
prom_ready() {
  [ "$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:${PROM_PORT}/-/ready" 2>/dev/null)" = "200" ] \
  && curl -s "http://localhost:${PROM_PORT}/api/v1/query?query=up" 2>/dev/null | grep -q '"status":"success"'
}
gf_ready() {
  # ⚠️ 2026-09-04 实测（课 2 修正）：Grafana 的 /api/health 返回的是【带空格缩进】的 JSON
  #    {"database": "ok", ...}   ← 冒号后有空格
  #    而 Prometheus 的 API 返回的是【紧凑】JSON："status":"success"
  #    两者风格不一致！用 grep -q '"database":"ok"' 是【恒假】的，永远匹配不上。
  #    故此处先 tr -d ' \n' 压平所有空白，再用紧凑写法匹配——两种风格通吃。
  curl -s "http://localhost:${GF_PORT}/api/health" 2>/dev/null \
    | tr -d ' \n' | grep -q '"database":"ok"'
}
ne_ready() {
  curl -s "http://localhost:${NE_PORT}/metrics" 2>/dev/null | grep -q 'node_cpu_seconds_total'
}

# ⚠️ 2026-09-04 实测（课 2 修正了课 1 的错误归因）：
#    Grafana 启动约 6 秒 /api/health 即就绪；之后后台联网安装 5 个插件
#    （metricsdrilldown / exploretraces / pyroscope / advisor / lokiexplore），
#    在 t+11s ~ t+19s 陆续装完。
#    即：【health 就绪（6s）早于插件装完（19s）13 秒，插件安装不阻塞可用性】。
#    课 1 曾把探测失败归因于"装插件慢 60 秒"，是错的——
#    真正原因是当时 gf_ready 用了紧凑写法 grep '"database":"ok"'（恒假），
#    而 Grafana 实际返回的是带空格的 '"database": "ok"'。判据已修正。
#    保留 90 次×2s 的余量是为了应对首次拉镜像/慢盘等极端情况，非插件所需。
echo "  （Grafana 通常 6 秒左右就绪，此处留 3 分钟余量应对慢环境…）"
for i in $(seq 1 90); do
  if prom_ready && gf_ready && ne_ready; then
    echo "  第 ${i} 次探测（约 $((i*2)) 秒）：三个组件全部就绪（已验证身份，非仅状态码）"
    break
  fi
  sleep 2
done

echo "=== 6. 最终状态（含身份校验）==="
echo -n "  Grafana    /api/health    -> "; gf_ready && echo "200 且 database=ok ✅" || echo "未就绪 ❌"
echo -n "  Prometheus /-/ready+query -> "; prom_ready && echo "200 且返回 status=success ✅" || echo "未就绪 ❌"
echo -n "  node-expo  /metrics       -> "; ne_ready && echo "200 且含 node_cpu_seconds_total ✅" || echo "未就绪 ❌"

echo "  Prometheus 实际抓到的 targets:"
curl -s "http://localhost:${PROM_PORT}/api/v1/targets" \
  | python3 -c 'import sys,json;d=json.load(sys.stdin);[print(f"    - job={t["labels"]["job"]} health={t["health"]}") for t in d["data"]["activeTargets"]]' 2>/dev/null \
  || echo "    （解析失败，手动查：curl http://localhost:${PROM_PORT}/api/v1/targets）"
