#!/bin/bash
# 课 10 实验 2（最终版）：vmauth 认证 + 租户路由 + 负载均衡
# 已探明的路径规则：
#   最终路径 = url_prefix + 原始请求路径
#   查询: /select/<T>/prometheus/api/v1/...   ← 必须有 prometheus 段
#   写入: /insert/<T>/influx/write            ← Influx 行协议
#         /insert/<T>/prometheus/api/v1/write ← remote write (snappy)
set -u
NET=vm-cluster-net
PLAY=/mnt/d/projects/learning/victoriametrics/playground
CFG=$PLAY/vmauth-config.yml

cat > "$CFG" <<'YML'
# vmauth 配置：按 Basic Auth 身份路由到固定租户
#
# ⚠️ 核心规则：最终路径 = url_prefix + 原始请求路径
#    集群版路径含 /prometheus 或 /influx 段，url_prefix 必须补齐

users:
  # 租户 A：后端团队 → tenant 100
  - username: "backend"
    password: "backend-pass-123"
    url_map:
      # 写入：客户端访问 /write（Influx 行协议）
      - src_paths: ["/write"]
        url_prefix: ["http://vminsert-learn:8480/insert/100/influx"]
      # 写入：客户端访问 /api/v1/write（Prometheus remote write）
      - src_paths: ["/api/v1/write"]
        url_prefix: ["http://vminsert-learn:8480/insert/100/prometheus"]
      # 查询：负载均衡到两个 vmselect
      - src_paths:
          - "/api/v1/query"
          - "/api/v1/query_range"
          - "/api/v1/labels"
          - "/api/v1/label/.+/values"
          - "/api/v1/status/tsdb"
        url_prefix:
          - "http://vmselect-learn:8481/select/100/prometheus"
          - "http://vmsel-dedup:8481/select/100/prometheus"

  # 租户 B：前端团队 → tenant 200
  - username: "frontend"
    password: "frontend-pass-456"
    url_map:
      - src_paths: ["/write"]
        url_prefix: ["http://vminsert-learn:8480/insert/200/influx"]
      - src_paths: ["/api/v1/write"]
        url_prefix: ["http://vminsert-learn:8480/insert/200/prometheus"]
      - src_paths:
          - "/api/v1/query"
          - "/api/v1/query_range"
          - "/api/v1/labels"
          - "/api/v1/label/.+/values"
          - "/api/v1/status/tsdb"
        url_prefix:
          - "http://vmselect-learn:8481/select/200/prometheus"
          - "http://vmsel-dedup:8481/select/200/prometheus"

  # 只读观察者 → 只能查 tenant 100，无写入路由
  - username: "viewer"
    password: "viewer-pass-000"
    url_map:
      - src_paths:
          - "/api/v1/query"
          - "/api/v1/query_range"
        url_prefix:
          - "http://vmselect-learn:8481/select/100/prometheus"
YML

echo "=============================================="
echo " F1 重启 vmauth（最终配置）"
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
docker logs vmauth-learn 2>&1 | grep 'loaded information' | head -1

echo
echo "=============================================="
echo " F2 认证矩阵"
echo "=============================================="
printf "   %-26s " "无凭证": ; curl -s -o /dev/null -w 'HTTP %{http_code}\n' --max-time 20 --data-urlencode 'query=up' 'http://localhost:8427/api/v1/query'
printf "   %-26s " "错密码": ; curl -s -o /dev/null -w 'HTTP %{http_code}\n' --max-time 20 -u backend:wrong --data-urlencode 'query=up' 'http://localhost:8427/api/v1/query'
printf "   %-26s " "backend(正确)": ; curl -s -o /dev/null -w 'HTTP %{http_code}\n' --max-time 20 -u backend:backend-pass-123 --data-urlencode 'query=up' 'http://localhost:8427/api/v1/query'
printf "   %-26s " "frontend(正确)": ; curl -s -o /dev/null -w 'HTTP %{http_code}\n' --max-time 20 -u frontend:frontend-pass-456 --data-urlencode 'query=up' 'http://localhost:8427/api/v1/query'
printf "   %-26s " "viewer(正确)": ; curl -s -o /dev/null -w 'HTTP %{http_code}\n' --max-time 20 -u viewer:viewer-pass-000 --data-urlencode 'query=up' 'http://localhost:8427/api/v1/query'

echo
echo "=============================================="
echo " F3 核心：租户由凭证决定，客户端不能自选"
echo "=============================================="
python3 - <<'PY'
import time
ts = (int(time.time()) - 120) * 1000000000
open("/tmp/l10_va.influx","w").write("\n".join("l10_va,idx=%d value=100 %d" % (i,ts) for i in range(5))+"\n")
open("/tmp/l10_vb.influx","w").write("\n".join("l10_va,idx=%d value=200 %d" % (i,ts) for i in range(5))+"\n")
print("  l10_va: backend 值=100 / frontend 值=200")
PY
echo
printf "  backend  写入 /write: "
curl -s -o /dev/null -w 'HTTP %{http_code}\n' -X POST --max-time 30 \
  -u backend:backend-pass-123 --data-binary @/tmp/l10_va.influx \
  'http://localhost:8427/write'
printf "  frontend 写入 /write: "
curl -s -o /dev/null -w 'HTTP %{http_code}\n' -X POST --max-time 30 \
  -u frontend:frontend-pass-456 --data-binary @/tmp/l10_vb.influx \
  'http://localhost:8427/write'

sleep 8

echo
echo "  -- 各自查询，应只看到自己的值 --"
for u in backend:backend-pass-123 frontend:frontend-pass-456 viewer:viewer-pass-000; do
  printf "    %-10s " "${u%%:*}"
  curl -s --max-time 30 -u "$u" --data-urlencode 'query=l10_va_value' \
    'http://localhost:8427/api/v1/query' \
    | python3 -c 'import json,sys
try:
    d=json.load(sys.stdin); r=d.get("data",{}).get("result",[])
    print(sorted(set(x["value"][1] for x in r)) if r else "空")
except Exception: print("解析失败")' 2>&1
done
echo "      （viewer 应看到 100，因为它映射的是 tenant 100）"

echo
echo "  -- 绕过 vmauth 直连后端核对 --"
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
echo " F4 权限边界测试"
echo "=============================================="
printf "  viewer 尝试写入:            "
curl -s -o /dev/null -w 'HTTP %{http_code}\n' -X POST --max-time 20 \
  -u viewer:viewer-pass-000 --data-binary @/tmp/l10_va.influx \
  'http://localhost:8427/write'
printf "    └ 响应: "
curl -s -X POST --max-time 20 -u viewer:viewer-pass-000 \
  --data-binary @/tmp/l10_va.influx 'http://localhost:8427/write' 2>&1 | tail -1
echo
printf "  backend 尝试自选租户:       "
curl -s -o /dev/null -w 'HTTP %{http_code}\n' --max-time 20 -u backend:backend-pass-123 \
  --data-urlencode 'query=l10_va_value' \
  'http://localhost:8427/select/200/prometheus/api/v1/query'
printf "    └ 响应: "
curl -s --max-time 20 -u backend:backend-pass-123 \
  --data-urlencode 'query=l10_va_value' \
  'http://localhost:8427/select/200/prometheus/api/v1/query' 2>&1 | tail -1

echo
echo "=============================================="
echo " F5 负载均衡（least_loaded 默认策略）"
echo "=============================================="
for i in $(seq 1 20); do
  curl -s -o /dev/null --max-time 20 -u backend:backend-pass-123 \
    --data-urlencode 'query=up' 'http://localhost:8427/api/v1/query'
done
echo "  -- vmauth 记录的后端请求分布 --"
curl -s --max-time 15 'http://localhost:8427/metrics' 2>/dev/null \
  | grep -E 'vmauth_http_requests_total|vmauth_user_requests' | head -10

echo
echo "=============================================="
echo " F6 vmauth 的可观测性指标"
echo "=============================================="
curl -s --max-time 15 'http://localhost:8427/metrics' 2>/dev/null \
  | grep -E '^vmauth_' | head -15

echo
echo "=============================================="
echo " F7 热重载：改配置不重启"
echo "=============================================="
echo "  vmauth 支持 /-/reload 热重载配置"
printf "    重载前用户数: "
docker logs vmauth-learn 2>&1 | grep -c 'loaded information'
curl -s -o /dev/null -w 'HTTP %{http_code}\n' --max-time 10 \
  'http://localhost:8427/-/reload'
sleep 2
echo "    （HTTP 200 = 重载成功）"
