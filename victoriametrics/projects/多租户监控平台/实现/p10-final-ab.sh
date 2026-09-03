#!/usr/bin/env bash
# ============================================================
# 终局验证：用两个并行 vmagent 做真对照
#
# 上一轮的失败原因：docker cp 覆盖不了 bind mount 的只读文件
#   （device or resource busy），对照组根本没换上配置。
#
# 本轮做法：起两个 vmagent 抓同一个 exporter，
#   vmagent-main  : 带 metric_relabel_configs 的 labeldrop
#   vmagent-nodrop: 不带 labeldrop
#   两者写入不同的 accountID（101 / 102），互不干扰。
# ============================================================
set -uo pipefail
PROJ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJ/实现"
NET="vm-capstone-net"
VMSELECT="http://localhost:8501"
hdr() { echo; echo "=== $* ==="; }

hdr "准备：确保基础环境在跑"
docker ps --format '{{.Names}}' | grep -q '^capstone-exporter-a$' || {
  echo "  exporter 未运行，先拉起基础环境"
  bash p01-up.sh >/dev/null 2>&1
  sleep 20
}

hdr "生成两份对照配置"
cat > /tmp/cfg-drop.yml <<'EOF'
global:
  scrape_interval: 5s
  scrape_timeout: 4s
scrape_configs:
  - job_name: ab-with-labeldrop
    metrics_path: /metrics
    static_configs:
      - targets: ["capstone-exporter-a:9100"]
        labels:
          tenant: tenant-a
          arm: with-labeldrop
    relabel_configs:
      - source_labels: [__address__]
        target_label: instance
        regex: "capstone-exporter-a:9100"
        replacement: "backend-01"
    metric_relabel_configs:
      - action: labeldrop
        regex: "(user_id|request_id|trace_id)"
EOF

cat > /tmp/cfg-nodrop.yml <<'EOF'
global:
  scrape_interval: 5s
  scrape_timeout: 4s
scrape_configs:
  - job_name: ab-no-labeldrop
    metrics_path: /metrics
    static_configs:
      - targets: ["capstone-exporter-a:9100"]
        labels:
          tenant: tenant-a
          arm: no-labeldrop
EOF

echo "  /tmp/cfg-drop.yml   （带 labeldrop）"
echo "  /tmp/cfg-nodrop.yml （不带 labeldrop）"

hdr "启动两个对照 vmagent"
docker rm -f ab-drop ab-nodrop >/dev/null 2>&1 || true

docker run -d --name ab-drop --network "$NET" \
  -v /tmp/cfg-drop.yml:/etc/prometheus/prometheus.yml:ro \
  victoriametrics/vmagent:v1.151.0 \
  -promscrape.config=/etc/prometheus/prometheus.yml \
  -remoteWrite.url=http://capstone-vminsert:8480/insert/101/prometheus/api/v1/write \
  -remoteWrite.tmpDataPath=/tmp/ab-drop \
  -httpListenAddr=:8429 >/dev/null

docker run -d --name ab-nodrop --network "$NET" \
  -v /tmp/cfg-nodrop.yml:/etc/prometheus/prometheus.yml:ro \
  victoriametrics/vmagent:v1.151.0 \
  -promscrape.config=/etc/prometheus/prometheus.yml \
  -remoteWrite.url=http://capstone-vminsert:8480/insert/102/prometheus/api/v1/write \
  -remoteWrite.tmpDataPath=/tmp/ab-nodrop \
  -httpListenAddr=:8429 >/dev/null

echo "  ab-drop   -> accountID 101"
echo "  ab-nodrop -> accountID 102"
echo "  等待 60 秒采集"
sleep 60

hdr "结果对比：各自 accountID 里 app_user_activity_total 的序列数"

stat_tenant() {
  local acct="$1"
  curl -s --get "$VMSELECT/select/$acct/prometheus/api/v1/series" \
    --data-urlencode 'match[]=app_user_activity_total' 2>/dev/null \
    | python3 -c '
import json,sys
try:
    d=json.load(sys.stdin)
    rows=d.get("data",[]) or []
    uid=[r for r in rows if "user_id" in r]
    print("    总序列数 = %-4d  带 user_id = %-4d" % (len(rows), len(uid)))
    if rows:
        print("    样例：", json.dumps(rows[0], sort_keys=True, ensure_ascii=False))
except Exception as e:
    print("    读取失败:", e)
'
}

echo "  [实验组 101] 带 metric_relabel_configs + labeldrop："
stat_tenant 101
echo
echo "  [对照组 102] 不带任何 relabel："
stat_tenant 102

hdr "结论判定"
UID101=$(curl -s --get "$VMSELECT/select/101/prometheus/api/v1/series" \
  --data-urlencode 'match[]=app_user_activity_total' 2>/dev/null \
  | python3 -c 'import json,sys; d=json.load(sys.stdin); print(len([r for r in (d.get("data") or []) if "user_id" in r]))')
UID102=$(curl -s --get "$VMSELECT/select/102/prometheus/api/v1/series" \
  --data-urlencode 'match[]=app_user_activity_total' 2>/dev/null \
  | python3 -c 'import json,sys; d=json.load(sys.stdin); print(len([r for r in (d.get("data") or []) if "user_id" in r]))')

echo "  ┌───────────────────────────────────────────────────────┐"
echo "  │ 实验组（有 labeldrop）带 user_id 的序列数 = $UID101"
echo "  │ 对照组（无 labeldrop）带 user_id 的序列数 = $UID102"
if [ "$UID102" -gt 0 ] 2>/dev/null && [ "$UID101" = "0" ] 2>/dev/null; then
  echo "  │ ✅ 判定：metric_relabel_configs + labeldrop 【确实生效】"
  echo "  │    之前的失败是「旧数据残留」+「docker cp 覆盖失败」两个坑叠加"
else
  echo "  │ 判定结果见上，需人工复核"
fi
echo "  └───────────────────────────────────────────────────────┘"
