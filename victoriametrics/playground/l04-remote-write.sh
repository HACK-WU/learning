#!/usr/bin/env bash
# 课 4 步骤 1：启动 Prometheus 并通过 remote write 接入 VM
set -u

echo "===== 1. 启动 Prometheus（端口 9090）====="
docker rm -f prom-learn >/dev/null 2>&1
docker run -d --name prom-learn \
  --network host \
  -v /mnt/d/projects/learning/victoriametrics/playground/prometheus.yml:/etc/prometheus/prometheus.yml:ro \
  prom/prometheus:v2.53.0 \
  --config.file=/etc/prometheus/prometheus.yml \
  --web.listen-address=:9090 \
  --web.enable-lifecycle

echo "  等待 Prometheus 启动..."
for i in $(seq 1 30); do
  code=$(curl -s -o /dev/null -w '%{http_code}' -m 3 http://localhost:9090/-/healthy 2>/dev/null)
  [ "$code" = "200" ] && { echo "  Prometheus 就绪 (${i}s)"; break; }
  sleep 1
done

echo
echo "===== 2. 检查 remote_write 配置是否被 Prometheus 接受 ====="
curl -s -m 5 http://localhost:9090/api/v1/status/config \
  | python3 -c 'import sys,yaml;c=yaml.safe_load(sys.stdin)["data"]["yaml"];print(c)' 2>/dev/null | head -30

echo
echo "===== 3. 等 remote write 把数据推进 VM（等 40 秒）====="
sleep 40

echo
echo "===== 4. 在 VM 侧查询由 remote write 写入的指标 ====="
for q in 'up' 'prometheus_remote_storage_samples_total' 'prometheus_tsdb_head_series'; do
  echo "--- $q ---"
  curl -s -m 15 -G http://localhost:8428/api/v1/query \
    --data-urlencode "query=$q" --data-urlencode "nocache=1" \
  | python3 -c '
import sys,json
d=json.load(sys.stdin)
if d.get("status")!="success":
    print("    ERROR:", str(d.get("error","?"))[:100]); sys.exit()
r=d["data"]["result"]
print(f"    命中 {len(r)} 条")
for it in r[:5]:
    m=it["metric"]; name=m.get("__name__","<无名称>")
    labs={k:v for k,v in m.items() if k!="__name__"}
    print(f"      {name} {labs} = {it[\"value\"][1]}")
'
done

echo
echo "===== 5. 验证 external_labels 是否生效 ====="
echo "--- up{datacenter=...} ---"
curl -s -m 15 -G http://localhost:8428/api/v1/query \
  --data-urlencode 'query=up{datacenter="dc-learn"}' --data-urlencode "nocache=1" \
| python3 -c '
import sys,json
r=json.load(sys.stdin)["data"]["result"]
print(f"    命中 {len(r)} 条（external_labels 生效则 >0）")
for it in r[:5]:
    m=it["metric"]
    print("      ", {k:v for k,v in m.items() if k!="__name__"}, "=", it["value"][1])
'

echo
echo "===== 6. 验证 write_relabel_configs 的 drop 是否生效 ====="
echo "--- count(go_gc_*)（应为 0，被 drop 了）---"
curl -s -m 15 -G http://localhost:8428/api/v1/query \
  --data-urlencode 'query=count({__name__=~"go_gc_.*"})' --data-urlencode "nocache=1" \
| python3 -c 'import sys,json;r=json.load(sys.stdin)["data"]["result"];print("    结果:", r[0]["value"][1] if r else "0 条（空）")'
echo "--- count(go_goroutines)（对照组，应 >0）---"
curl -s -m 15 -G http://localhost:8428/api/v1/query \
  --data-urlencode 'query=count(go_goroutines)' --data-urlencode "nocache=1" \
| python3 -c 'import sys,json;r=json.load(sys.stdin)["data"]["result"];print("    结果:", r[0]["value"][1] if r else "0 条（空）")'

echo
echo "===== 7. 验证 metric_relabel_configs 的 drop 是否生效 ====="
echo "--- count(prometheus_http_request_duration_seconds_*)（应远少于 Prometheus 本地）---"
curl -s -m 15 -G http://localhost:8428/api/v1/query \
  --data-urlencode 'query=count({__name__=~"prometheus_http_request_duration_seconds_.*"})' \
  --data-urlencode "nocache=1" \
| python3 -c 'import sys,json;r=json.load(sys.stdin)["data"]["result"];print("    VM 侧:", r[0]["value"][1] if r else "0 条（空）")'
curl -s -m 15 -G http://localhost:9090/api/v1/query \
  --data-urlencode 'query=count({__name__=~"prometheus_http_request_duration_seconds_.*"})' \
| python3 -c 'import sys,json;r=json.load(sys.stdin)["data"]["result"];print("    Prometheus 本地:", r[0]["value"][1] if r else "0 条（空）")'

echo
echo "===== 8. Prometheus 侧 remote write 状态 ====="
curl -s -m 10 http://localhost:9090/api/v1/status/config \
  | python3 -c 'import sys,yaml;print("    remote_write 已加载")' 2>/dev/null
echo "  --- 关键指标（Prometheus 本地查）---"
for q in prometheus_remote_storage_samples_total prometheus_remote_storage_samples_failed_total prometheus_remote_storage_shards; do
  v=$(curl -s -m 10 -G http://localhost:9090/api/v1/query --data-urlencode "query=$q" \
    | python3 -c 'import sys,json;r=json.load(sys.stdin)["data"]["result"];print(r[0]["value"][1] if r else "(空)")' 2>/dev/null)
  
echo "  $q = $v"
done
