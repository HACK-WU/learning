#!/usr/bin/env bash
# 课 9 命令复验：逐条跑讲义第四幕的命令，断言预期结果
# 用法：bash verify-part4.sh
set -uo pipefail
NET=l9net
PASS=0; FAIL=0

ok()   { PASS=$((PASS+1)); echo "  [PASS] $1"; }
bad()  { FAIL=$((FAIL+1)); echo "  [FAIL] $1  (实际: $2)"; }

chk() { # $1=描述 $2=实际 $3=期望
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "$2 != $3"; fi
}

echo "==================== 实验 0：环境准备 ===================="
n=$(docker ps --format '{{.Names}}' | grep -c '^l9-' || true)
echo "  当前 l9-* 容器数: $n"
[ "$n" -gt 0 ] && ok "环境已就绪" || bad "环境未就绪" "$n"

echo
echo "==================== 实验 1：Thanos 拓扑 ===================="
for c in l9-prom-1 l9-prom-2 l9-thanos-sc-1 l9-thanos-sc-2 l9-thanos-store l9-thanos-query; do
  s=$(docker inspect -f '{{.State.Status}}' $c 2>/dev/null || echo missing)
  chk "$c running" "$s" "running"
done

nstore=$(docker run --rm --network $NET curlimages/curl:latest -s \
  http://l9-thanos-query:19191/api/v1/stores 2>/dev/null \
  | python3 -c "
import sys,json
d=json.load(sys.stdin)['data']
print(len(d.get('sidecar',[]))+len(d.get('store',[])))")
chk "Thanos 发现 3 个 store" "$nstore" "3"

up=$(docker run --rm --network $NET curlimages/curl:latest -s -G \
  --data-urlencode 'query=up' http://l9-thanos-query:19191/api/v1/query 2>/dev/null \
  | python3 -c "
import sys,json
d=json.load(sys.stdin); rs=d['data']['result']
print(rs[0]['value'][1] if rs else 'N/A')")
chk "up 指标为 1（数据源活着）" "$up" "1"

echo
echo "==================== 实验 1：HA 去重决定性对照 ===================="
q1=$(docker run --rm --network $NET curlimages/curl:latest -s -G \
  --data-urlencode 'query=count(app_requests_total{route="/"})' \
  http://l9-thanos-query:19191/api/v1/query 2>/dev/null \
  | python3 -c "
import sys,json
d=json.load(sys.stdin); rs=d['data']['result']
print(rs[0]['value'][1] if rs else 'N/A')")
q2=$(docker run --rm --network $NET curlimages/curl:latest -s -G \
  --data-urlencode 'query=count(app_requests_total{route="/"})' \
  http://l9-thanos-query-nodedup:19191/api/v1/query 2>/dev/null \
  | python3 -c "
import sys,json
d=json.load(sys.stdin); rs=d['data']['result']
print(rs[0]['value'][1] if rs else 'N/A')")
chk "Q1(去重开) count=1" "$q1" "1"
chk "Q2(去重关) count=2" "$q2" "2"

echo
echo "==================== 实验 2：字段名判定 ===================="
for f in "bucket_lookup_type: path" "force_s3_path_style: true" "s3forcepathstyle: true"; do
  cat > /tmp/v-bucket.yml <<EOF
type: S3
config:
  bucket: thanos
  endpoint: l9-minio:9000
  access_key: minioadmin
  secret_key: minioadmin
  insecure: true
  $f
EOF
  out=$(docker run --rm --network $NET \
    -v /tmp/v-bucket.yml:/etc/thanos/bucket.yml:ro \
    --entrypoint sh quay.io/thanos/thanos:v0.42.4 -c \
    "timeout 12 /bin/thanos store --objstore.config-file=/etc/thanos/bucket.yml \
     --data-dir=/tmp/ts --http-address=0.0.0.0:19191 --grpc-address=0.0.0.0:19090 2>&1 | head -20")
  if echo "$out" | grep -q 'not found in type'; then r=REJECTED; else r=ACCEPTED; fi
  case "$f" in
    "bucket_lookup_type: path") chk "bucket_lookup_type 被接受" "$r" "ACCEPTED" ;;
    *) chk "$f 被拒绝" "$r" "REJECTED" ;;
  esac
done

echo
echo "==================== 实验 3：Mimir 多租户 ===================="
s=$(docker inspect -f '{{.State.Status}}' l9-mimir 2>/dev/null || echo missing)
chk "l9-mimir running" "$s" "running"

c401=$(docker run --rm --network $NET curlimages/curl:latest -s -o /dev/null -w '%{http_code}' \
  -X POST http://l9-mimir:8080/api/v1/push 2>/dev/null)
chk "无租户头写入 -> 401" "$c401" "401"

c400=$(docker run --rm --network $NET curlimages/curl:latest -s -o /dev/null -w '%{http_code}' \
  -X POST -H 'X-Scope-OrgID: t' http://l9-mimir:8080/api/v1/push 2>/dev/null)
chk "有租户头写入(空body) -> 400" "$c400" "400"

cross=$(docker run --rm --network $NET curlimages/curl:latest -s -G \
  -H 'X-Scope-OrgID: tenantA' \
  --data-urlencode 'query=app_requests_total{tenant="tenantB"}' \
  http://l9-mimir:8080/prometheus/api/v1/query 2>/dev/null \
  | python3 -c "
import sys,json
d=json.load(sys.stdin); print(len(d['data']['result']))")
chk "tenantA 查 tenantB -> 0 条" "$cross" "0"

ta=$(docker run --rm --network $NET curlimages/curl:latest -s -G \
  -H 'X-Scope-OrgID: tenantA' \
  --data-urlencode 'query=count(app_requests_total)' \
  http://l9-mimir:8080/prometheus/api/v1/query 2>/dev/null \
  | python3 -c "
import sys,json
d=json.load(sys.stdin); rs=d['data']['result']
print(rs[0]['value'][1] if rs else 'N/A')")
echo "  [INFO] tenantA count = $ta"

echo
echo "==================== 实验 3：Mimir distroless ===================="
sh_out=$(docker run --rm --entrypoint sh grafana/mimir:3.2.0 -c 'echo hi' 2>&1 || true)
if echo "$sh_out" | grep -q 'not found'; then ok "distroless 无 shell（符合预期）"
else bad "distroless 判定" "$sh_out"; fi

echo
echo "==================== 实验 4：VM 路径差异 ===================="
c1=$(docker run --rm --network $NET curlimages/curl:latest -s -o /dev/null -w '%{http_code}' -G \
  --data-urlencode 'query=up' http://l9-vm-single:8428/prometheus/api/v1/query 2>/dev/null)
chk "VM 单节点 /prometheus/api/v1/query -> 200" "$c1" "200"

c2=$(docker run --rm --network $NET curlimages/curl:latest -s -o /dev/null -w '%{http_code}' -G \
  --data-urlencode 'query=up' http://l9-vmselect:8481/prometheus/api/v1/query 2>/dev/null)
chk "VM 集群 同路径 -> 400" "$c2" "400"

c3=$(docker run --rm --network $NET curlimages/curl:latest -s -o /dev/null -w '%{http_code}' -G \
  --data-urlencode 'query=up' http://l9-vmselect:8481/select/0/prometheus/api/v1/query 2>/dev/null)
chk "VM 集群 /select/0/ 前缀 -> 200" "$c3" "200"

echo
echo "==================== 实验 5：OTLP ===================="
# 注意：实际 flag 写作 --[no-]web.enable-otlp-receiver（带 [no-] 前缀）
h=$(docker run --rm prom/prometheus:v3.14.0 --help 2>/dev/null \
  | grep -c -- 'web.enable-otlp-receiver')
chk "--web.enable-otlp-receiver 存在于 help" "$h" "1"

# 2.x 的 feature 写法应已不在 feature 列表里
# （feature 列表里仍有 otlp-deltatocumulative / otlp-native-delta-ingestion，
#   但不应有 otlp-write-receiver 作为 feature flag）
h2=$(docker run --rm prom/prometheus:v3.14.0 --help 2>/dev/null \
  | grep -c 'enable-feature=otlp-write-receiver')
chk "--enable-feature=otlp-write-receiver 已移除" "$h2" "0"

echo
echo "==================== 汇总 ===================="
echo "  PASS=$PASS  FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && echo "  ✅ 全部通过" || echo "  ❌ 有失败项"
