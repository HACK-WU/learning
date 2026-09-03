#!/usr/bin/env bash
# ============================================================
# 多租户监控平台 · 一键启动
#
# 拓扑：
#   exporter-a (degraded)  ─┐
#   exporter-b (healthy)   ─┤
#                           ├─> vmagent-a -> vminsert(accountID 100)
#   (vmagent 自监控)       ─┘   vmagent-b -> vminsert(accountID 200)
#                                              |
#                                        vmstorage x2
#                                              |
#                                        vmselect
#                                              |
#                                           vmauth (:8427)
#
# 用法：
#   bash p01-up.sh            # 拉起整套
#   bash p01-up.sh --reset    # 清空数据后重建（用于可重复实验）
# ============================================================
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$(cd "$HERE/.." && pwd)"
NET="vm-capstone-net"
RESET=0
[ "${1:-}" = "--reset" ] && RESET=1

log()  { echo "[up] $*"; }

# ---------- 清理旧环境 ----------
log "清理旧容器（若存在）"
for c in capstone-vmauth capstone-vmalert capstone-vmalert-a capstone-vmalert-b capstone-alertmanager \
         capstone-vmagent-a capstone-vmagent-b \
         capstone-vmselect capstone-vminsert \
         capstone-vmstorage-1 capstone-vmstorage-2 \
         capstone-exporter-a capstone-exporter-b; do
  docker rm -f "$c" >/dev/null 2>&1 || true
done

if [ "$RESET" = "1" ]; then
  log "清空数据目录（bind mount 到宿主机，必须清宿主机目录）"
  # ⚠ 坑：数据不在 docker volume 里，而在 bind mount 的宿主机目录。
  #   用 docker run --rm -v xxx:/d alpine rm -rf 去清一个不存在的 volume 是无效的，
  #   容器照样能起来、旧数据照样还在 —— 表现为「改了配置却像没生效」。
  rm -rf "$PROJ/data/storage-1" "$PROJ/data/storage-2"
fi

mkdir -p "$PROJ/data/storage-1" "$PROJ/data/storage-2"
docker network create "$NET" >/dev/null 2>&1 || true

# ---------- 1. 两个业务导出器 ----------
log "启动 exporter-a（tenant-a / degraded：注入 5% 错误 + 3x 延迟）"
docker run -d --name capstone-exporter-a --network "$NET" \
  -v "$PROJ/实现/exporter.py:/app/exporter.py:ro" \
  python:3.12-slim \
  python3 /app/exporter.py --tenant tenant-a --scenario degraded --rps 20 --users 50 \
  >/dev/null

log "启动 exporter-b（tenant-b / healthy）"
docker run -d --name capstone-exporter-b --network "$NET" \
  -v "$PROJ/实现/exporter.py:/app/exporter.py:ro" \
  python:3.12-slim \
  python3 /app/exporter.py --tenant tenant-b --scenario healthy --rps 20 --users 50 \
  >/dev/null

# ---------- 2. 集群存储层：2 个 vmstorage ----------
log "启动 vmstorage x2（复制因子 2）"
docker run -d --name capstone-vmstorage-1 --network "$NET" \
  -v "$PROJ/data/storage-1:/vmdata" \
  victoriametrics/vmstorage:v1.151.0-cluster \
  --storageDataPath=/vmdata --retentionPeriod=7d --httpListenAddr=:8482 \
  --vminsertAddr=:8400 --vmselectAddr=:8401 \
  >/dev/null

docker run -d --name capstone-vmstorage-2 --network "$NET" \
  -v "$PROJ/data/storage-2:/vmdata" \
  victoriametrics/vmstorage:v1.151.0-cluster \
  --storageDataPath=/vmdata --retentionPeriod=7d --httpListenAddr=:8482 \
  --vminsertAddr=:8400 --vmselectAddr=:8401 \
  >/dev/null

# ---------- 3. vminsert / vmselect ----------
log "启动 vminsert"
docker run -d --name capstone-vminsert --network "$NET" -p 8500:8480 \
  victoriametrics/vminsert:v1.151.0-cluster \
  --storageNode=capstone-vmstorage-1:8400,capstone-vmstorage-2:8400 \
  --replicationFactor=2 \
  >/dev/null

log "启动 vmselect"
docker run -d --name capstone-vmselect --network "$NET" -p 8501:8481 \
  victoriametrics/vmselect:v1.151.0-cluster \
  --storageNode=capstone-vmstorage-1:8401,capstone-vmstorage-2:8401 \
  --dedup.minScrapeInterval=5s \
  >/dev/null

# ---------- 4. 两个 vmagent，各自写入自己租户 ----------
# 租户隔离的第一道闸：靠不同的 remoteWrite.url 里的 accountID
log "启动 vmagent-a -> accountID 100"
docker run -d --name capstone-vmagent-a --network "$NET" -p 8502:8429 \
  -v "$PROJ/实现/prometheus-a.yml:/etc/prometheus/prometheus.yml:ro" \
  victoriametrics/vmagent:v1.151.0 \
  -promscrape.config=/etc/prometheus/prometheus.yml \
  -remoteWrite.url=http://capstone-vminsert:8480/insert/100/prometheus/api/v1/write \
  -remoteWrite.tmpDataPath=/tmp/vmagent-a \
  -httpListenAddr=:8429 \
  >/dev/null

log "启动 vmagent-b -> accountID 200"
docker run -d --name capstone-vmagent-b --network "$NET" -p 8503:8429 \
  -v "$PROJ/实现/prometheus-b.yml:/etc/prometheus/prometheus.yml:ro" \
  victoriametrics/vmagent:v1.151.0 \
  -promscrape.config=/etc/prometheus/prometheus.yml \
  -remoteWrite.url=http://capstone-vminsert:8480/insert/200/prometheus/api/v1/write \
  -remoteWrite.tmpDataPath=/tmp/vmagent-b \
  -httpListenAddr=:8429 \
  >/dev/null

# ---------- 5. alertmanager ----------
log "启动 alertmanager"
docker run -d --name capstone-alertmanager --network "$NET" -p 8504:9093 \
  -v "$PROJ/实现/alertmanager.yml:/etc/alertmanager/alertmanager.yml:ro" \
  prom/alertmanager:v0.27.0 \
  --config.file=/etc/alertmanager/alertmanager.yml \
  >/dev/null

# ---------- 6. vmalert：每个租户一个实例 ----------
# ⚠ 关键设计（这是多租户告警最容易踩的结构性坑）：
#   vmalert 只有一个 -datasource.url，所有规则共用同一个数据源。
#   如果用一个 vmalert 跑两个租户的规则，那么 tenant-b 的规则
#   实际查的是 tenant-a 的数据 —— 结果是：
#     * tenant-b 的 HighErrorRate 永远不响（查不到自己的错误率）
#     * tenant-b 的 absent() 类规则恒真，产生假告警
#   所以：租户隔离必须一路贯到告警层，每租户一个 vmalert。
#
# ⚠ 第二个坑：-remoteWrite.url 不要手写 /api/v1/write！
#   vmalert 会自动补这个后缀。写成
#     .../insert/100/prometheus/api/v1/write
#   实际会请求
#     .../insert/100/prometheus/api/v1/write/api/v1/write  -> 400
#   正确写法只到 .../insert/100/prometheus
log "启动 vmalert-a（租户 a，查 accountID 100）"
docker run -d --name capstone-vmalert-a --network "$NET" -p 8505:8880 \
  -v "$PROJ/实现/alerts-a.yml:/etc/alerts/a.yml:ro" \
  victoriametrics/vmalert:v1.151.0 \
  -rule=/etc/alerts/a.yml \
  -datasource.url=http://capstone-vmselect:8481/select/100/prometheus \
  -notifier.url=http://capstone-alertmanager:9093 \
  -remoteWrite.url=http://capstone-vminsert:8480/insert/100/prometheus \
  -external.label=cluster=capstone \
  -external.label=tenant=tenant-a \
  -httpListenAddr=:8880 \
  >/dev/null

log "启动 vmalert-b（租户 b，查 accountID 200）"
docker run -d --name capstone-vmalert-b --network "$NET" -p 8507:8880 \
  -v "$PROJ/实现/alerts-b.yml:/etc/alerts/b.yml:ro" \
  victoriametrics/vmalert:v1.151.0 \
  -rule=/etc/alerts/b.yml \
  -datasource.url=http://capstone-vmselect:8481/select/200/prometheus \
  -notifier.url=http://capstone-alertmanager:9093 \
  -remoteWrite.url=http://capstone-vminsert:8480/insert/200/prometheus \
  -external.label=cluster=capstone \
  -external.label=tenant=tenant-b \
  -httpListenAddr=:8880 \
  >/dev/null

# ---------- 7. vmauth：统一入口，按身份路由 ----------
log "启动 vmauth（统一入口 :8427）"
docker run -d --name capstone-vmauth --network "$NET" -p 8506:8427 \
  -v "$PROJ/实现/vmauth.yml:/etc/vmauth/config.yml:ro" \
  victoriametrics/vmauth:v1.151.0 \
  -auth.config=/etc/vmauth/config.yml \
  >/dev/null

log "等待组件就绪"
sleep 12

log "容器状态："
docker ps --format 'table {{.Names}}\t{{.Status}}' | grep capstone || true

log "完成。下一步：bash p02-verify.sh"
