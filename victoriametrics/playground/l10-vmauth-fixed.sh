#!/bin/bash
# 课 10 实验 2（修正版）：vmauth 认证与路由
# 修复：url_prefix 必须补上 /prometheus 段
#   vmauth 拼接规则 = url_prefix + 原始请求路径
set -u
NET=vm-cluster-net
PLAY=/mnt/d/projects/learning/victoriametrics/playground
CFG=$PLAY/vmauth-config.yml

cat > "$CFG" <<'YML'
# vmauth 配置：按 Basic Auth 用户名路由到固定租户
#
# ⚠️ 关键规则：最终路径 = url_prefix + 原始请求路径
#    集群版真实路径含 /prometheus 段，所以 url_prefix 必须以它结尾

users:
  # 租户 A：后端团队 → tenant 100
  - username: "backend"
    password: "backend-pass-123"
    url_map:
      - src_paths:
          - "/api/v1/write"
          - "/api/v1/import"
        url_prefix:
          - "http://vminsert-learn:8480/insert/100/influx"
      - src_paths:
          - "/api/v1/query"
          - "/api/v1/query_range"
          - "/api/v1/labels"
          - "/api/v1/label/.+/values"
          - "/api/v1/series"
        url_prefix:
          - "http://vmselect-learn:8481/select/100/prometheus"
          - "http://vmsel-dedup:8481/select/100/prometheus"

  # 租户 B：前端团队 → tenant 200
  - username: "frontend"
    password: "frontend-pass-456"
    url_map:
      - src_paths:
          - "/api/v1/write"
          - "/api/v1/import"
        url_prefix:
          - "http://vminsert-learn:8480/insert/200/influx"
      - src_paths:
          - "/api/v1/query"
          - "/api/v1/query_range"
          - "/api/v1/labels"
          - "/api/v1/label/.+/values"
          - "/api/v1/series"
        url_prefix:
          - "http://vmselect-learn:8481/select/200/prometheus"
          - "http://vmsel-dedup:8481/select/200/prometheus"

  # 只读观察者 → tenant 100，但只允许查询
  - username: "viewer"
    password: "viewer-pass-000"
    url_map:
      - src_paths:
          - "/api/v1/query"
          - "/api/v1/query_range"
          - "/api/v1/labels"
        url_prefix:
          - "http://vmselect-learn:8481/select/100/prometheus"
YML

echo "=============================================="
echo " V2' 用修正后的配置重启 vmauth"
echo "=============================================="
docker rm -f vmauth-learn >/dev/null 2>&1
docker run -d --name vmauth-learn \
  --network "$NET" -p 8427:8427 \
  -v "$CFG:/etc/vmauth/config.yml:ro" \
  victoriametrics/vmauth:v1.151.0 \
  -auth.config=/etc/vmauth/config.yml \
  -httpListenAddr=:8427 >/dev/null 2>&1

for i in $(seq 1 30); do
  c=$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 'http://localhost:8427/health' 2>/dev/null)
  if [ "$c" = "200" ]; then echo "  vmauth 就绪"; break; fi
  sleep 2
done
docker logs vmauth-learn 2>&1 | grep -E 'loaded information|error' | head -3

echo
echo "=============================================="
echo " V3' 认证测试"
echo "=============================================="
printf "   无凭证查询:             "
curl -s -o /dev/null -w 'HTTP %{http_code}\n' --max-time 20 \
  --data-urlencode 'query=up' 'http://localhost:8427/api/v1/query'
printf "   错误密码查询:           "
curl -s -o /dev/null -w 'HTTP %{http_code}\n' --max-time 20 -u backend:wrong \
  --data-urlencode 'query=up' 'http://localhost:8427/api/v1/query'
printf "   正确凭证(backend)查询:  "
curl -s -o /dev/null -w 'HTTP %{http_code}\n' --max-time 20 -u backend:backend-pass-123 \
  --data-urlencode 'query=up' 'http://localhost:8427/api/v1/query'
printf "   正确凭证(frontend)查询: "
curl -s -o /dev/null -w 'HTTP %{http_code}\n' --max-time 20 -u frontend:frontend-pass-456 \
  --data-urlencode 'query=up' 'http://localhost:8427/api/v1/query'

echo
echo "=============================================="
echo " V4' 核心验证：租户由凭证决定"
echo "=============================================="
python3 - <<'PY'
import time
ts = (int(time.time()) - 120) * 1000000000
open("/tmp/l10_va.influx","w").write(
    "\n".join("l10_va,idx=%d value=100 %d" % (i, ts) for i in range(5)) + "\n")
open("/tmp/l10_vb.influx","w").write(
    "\n".join("l10_va,idx=%d value=200 %d" % (i, ts) for i in range(5)) + "\n")
print("  准备 l10_va: backend 值=100, frontend 值=200")
PY

echo
printf "  backend  写入: "
curl -s -o /dev/null -w 'HTTP %{http_code}\n' -X POST --max-time 30 \
  -u backend:backend-pass-123 --data-binary @/tmp/l10_va.influx \
  'http://localhost:8427/api/v1/write'
printf "  frontend 写入: "
curl -s -o /dev/null -w 'HTTP %{http_code}\n' -X POST --max-time 30 \
  -u frontend:frontend-pass-456 --data-binary @/tmp/l10_vb.influx \
  'http://localhost:8427/api/v1/write'

sleep 8

echo
echo "  -- 各自查询，应只看到自己的值 --"
for u in backend:backend-pass-123 frontend:frontend-pass-456; do
  printf "    %-28s " "${u%%:*}"
  curl -s --max-time 30 -u "$u" --data-urlencode 'query=l10_va_value' \
    'http://localhost:8427/api/v1/query' \
    | python3 -c 'import json,sys
try:
    d=json.load(sys.stdin); r=d.get("data",{}).get("result",[])
    print(sorted(set(x["value"][1] for x in r)) if r else "空")
except Exception as e:
    print("解析失败")' 2>&1
done

echo
echo "  -- 绕过 vmauth 直连后端，确认数据落在不同租户 --"
for t in 100 200; do
  printf "    tenant %s: " "$t"
  curl -s --max-time 30 --data-urlencode 'query=l10_va_value' \
    "http://localhost:8481/select/$t/prometheus/api/v1/query" \
    | python3 -c 'import json,sys
d=json.load(sys.stdin); r=d.get("data",{}).get("result",[])
print(sorted(set(x["value"][1] for x in r)) if r else "空")' 2>&1
done

echo
echo "=============================================="
echo " V5 越权测试：backend 能读到 frontend 的数据吗？"
echo "=============================================="
echo "  -- 尝试在请求里自己指定租户 ID --"
printf "    backend 访问 /select/200/...: "
curl -s -o /dev/null -w 'HTTP %{http_code}\n' --max-time 20 -u backend:backend-pass-123 \
  --data-urlencode 'query=l10_va_value' \
  'http://localhost:8427/select/200/prometheus/api/v1/query'
echo "      (400/404 = vmauth 未配置该 src_path，请求被拒)"

echo
echo "  -- viewer（只读）尝试写入 --"
printf "    viewer 写入: "
curl -s -o /dev/null -w 'HTTP %{http_code}\n' -X POST --max-time 20 \
  -u viewer:viewer-pass-000 --data-binary @/tmp/l10_va.influx \
  'http://localhost:8427/api/v1/write'
echo -n "      "
curl -s -i -X POST --max-time 20 -u viewer:viewer-pass-000 \
  --data-binary @/tmp/l10_va.influx \
  'http://localhost:8427/api/v1/write' 2>&1 | tail -1

echo
echo "=============================================="
echo " V6 负载均衡验证：请求是否打到多个 vmselect"
echo "=============================================="
echo "  连发 10 次查询，看 vmauth 的后端计数指标"
for i in $(seq 1 10); do
  curl -s -o /dev/null --max-time 20 -u backend:backend-pass-123 \
    --data-urlencode 'query=up' 'http://localhost:8427/api/v1/query'
done
echo "  -- vmauth 后端请求分布 --"
curl -s --max-time 15 'http://localhost:8427/metrics' 2>/dev/null \
  | grep 'vmauth_http_requests_total' | head -8
echo
echo "  -- 各 vmselect 的请求计数 --"
for p in 8481 8487; do
  printf "    vmselect(%s): " "$p"
  curl -s --max-time 15 "http://localhost:$p/metrics" 2>/dev/null \
    | grep 'vm_http_requests_total{.*api_v1_query' | head -2 | tr '\n' ' '
  echo
done
