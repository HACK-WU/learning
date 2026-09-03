#!/bin/bash
# 课 10 实验 2：部署 vmauth 做认证与路由
set -u
NET=vm-cluster-net
PLAY=/mnt/d/projects/learning/victoriametrics/playground
CFG=$PLAY/vmauth-config.yml

echo "=============================================="
echo " V0 前置：不带 vmauth 时的裸奔状态"
echo "=============================================="
echo "  -- 任何人都能读写任意租户 --"
echo -n "   直接写 tenant 99: "
curl -s -o /dev/null -w 'HTTP %{http_code}\n' -X POST --max-time 20 \
  --data-binary 'l10_bare,idx=1 value=1' \
  'http://localhost:8480/insert/99/influx/write' 2>/dev/null
echo -n "   直接读 tenant 99: "
curl -s -o /dev/null -w 'HTTP %{http_code}\n' --max-time 20 \
  --data-urlencode 'query=count_over_time(l10_bare_value[1h])' \
  'http://localhost:8481/select/99/prometheus/api/v1/query' 2>/dev/null
echo "  → 集群组件【没有任何认证】，租户 ID 客户端随便填"

echo
echo "=============================================="
echo " V1 编写 vmauth 配置：两个租户，各自凭证"
echo "=============================================="
cat > "$CFG" <<'YML'
# vmauth 配置：按 Basic Auth 用户名路由到固定租户
users:
  # 租户 A：后端团队
  - username: "backend"
    password: "backend-pass-123"
    url_map:
      - src_paths:
          - "/api/v1/write"
          - "/api/v1/import"
        url_prefix:
          - "http://vminsert-learn:8480/insert/100/"
        # 写入只走 vminsert，且强制租户 100
      - src_paths:
          - "/api/v1/query"
          - "/api/v1/query_range"
          - "/api/v1/labels"
          - "/api/v1/label/.+/values"
          - "/api/v1/series"
        url_prefix:
          - "http://vmselect-learn:8481/select/100/"
          - "http://vmsel-dedup:8481/select/100/"
        # 查询负载均衡到两个 vmselect，强制租户 100

  # 租户 B：前端团队
  - username: "frontend"
    password: "frontend-pass-456"
    url_map:
      - src_paths:
          - "/api/v1/write"
          - "/api/v1/import"
        url_prefix:
          - "http://vminsert-learn:8480/insert/200/"
      - src_paths:
          - "/api/v1/query"
          - "/api/v1/query_range"
          - "/api/v1/labels"
          - "/api/v1/label/.+/values"
          - "/api/v1/series"
        url_prefix:
          - "http://vmselect-learn:8481/select/200/"
          - "http://vmsel-dedup:8481/select/200/"

  # 管理员：可访问所有租户（用 /select/<任意租户> 通配）
  - username: "admin"
    password: "admin-pass-789"
    url_map:
      - src_paths: ["/api/v1/.*"]
        url_prefix:
          - "http://vmselect-learn:8481/select/0/"
        # 管理员默认走 tenant 0
YML
echo "  配置已写入 $CFG"
echo
echo "  -- 配置要点 --"
echo "    1. username/password  → Basic Auth 凭证"
echo "    2. src_paths          → 对外暴露的路径（客户端看到的样子）"
echo "    3. url_prefix         → 后端真实地址，【租户 ID 写死在这里】"
echo "    4. 多个 url_prefix    → 自动负载均衡"
echo
echo "  ⚠️ 关键机制：客户端【不需要也不能】指定租户 ID，"
echo "     租户由 vmauth 根据认证身份决定"

echo
echo "=============================================="
echo " V2 启动 vmauth"
echo "=============================================="
docker rm -f vmauth-learn >/dev/null 2>&1
docker run -d --name vmauth-learn \
  --network "$NET" -p 8427:8427 \
  -v "$CFG:/etc/vmauth/config.yml:ro" \
  victoriametrics/vmauth:v1.151.0 \
  -auth.config=/etc/vmauth/config.yml \
  -httpListenAddr=:8427 2>&1 | tail -1

echo "  等待就绪..."
for i in $(seq 1 30); do
  c=$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 'http://localhost:8427/health' 2>/dev/null)
  if [ "$c" = "200" ]; then echo "  vmauth 就绪 (8427)"; break; fi
  sleep 2
done

echo
echo "  -- vmauth 启动日志 --"
docker logs vmauth-learn 2>&1 | tail -10

echo
echo "=============================================="
echo " V3 认证测试：无凭证 / 错凭证 / 正确凭证"
echo "=============================================="
echo -n "   无凭证查询:             "
curl -s -o /dev/null -w 'HTTP %{http_code}\n' --max-time 20 \
  --data-urlencode 'query=up' \
  'http://localhost:8427/api/v1/query' 2>/dev/null
echo -n "   错误密码查询:           "
curl -s -o /dev/null -w 'HTTP %{http_code}\n' --max-time 20 -u backend:wrong-pass \
  --data-urlencode 'query=up' \
  'http://localhost:8427/api/v1/query' 2>/dev/null
echo -n "   不存在用户查询:         "
curl -s -o /dev/null -w 'HTTP %{http_code}\n' --max-time 20 -u nobody:xxx \
  --data-urlencode 'query=up' \
  'http://localhost:8427/api/v1/query' 2>/dev/null
echo -n "   正确凭证(backend)查询:  "
curl -s -o /dev/null -w 'HTTP %{http_code}\n' --max-time 20 -u backend:backend-pass-123 \
  --data-urlencode 'query=up' \
  'http://localhost:8427/api/v1/query' 2>/dev/null
echo -n "   正确凭证(frontend)查询: "
curl -s -o /dev/null -w 'HTTP %{http_code}\n' --max-time 20 -u frontend:frontend-pass-456 \
  --data-urlencode 'query=up' \
  'http://localhost:8427/api/v1/query' 2>/dev/null

echo
echo "=============================================="
echo " V4 核心验证：租户由凭证决定，客户端不能自己指定"
echo "=============================================="
echo "  分别用 backend / frontend 各写 5 条同名不同值的序列"

python3 - <<'PY'
import time
ts = (int(time.time()) - 120) * 1000000000
open("/tmp/l10_va.influx","w").write(
    "\n".join("l10_va,idx=%d value=100 %d" % (i, ts) for i in range(5)) + "\n")
open("/tmp/l10_vb.influx","w").write(
    "\n".join("l10_va,idx=%d value=200 %d" % (i, ts) for i in range(5)) + "\n")
print("  准备: l10_va (backend 值=100, frontend 值=200)")
PY

echo
echo -n "  backend 写入:  "
curl -s -o /dev/null -w 'HTTP %{http_code}\n' -X POST --max-time 30 \
  -u backend:backend-pass-123 --data-binary @/tmp/l10_va.influx \
  'http://localhost:8427/api/v1/write' 2>/dev/null
echo -n "  frontend 写入: "
curl -s -o /dev/null -w 'HTTP %{http_code}\n' -X POST --max-time 30 \
  -u frontend:frontend-pass-456 --data-binary @/tmp/l10_vb.influx \
  'http://localhost:8427/api/v1/write' 2>/dev/null

sleep 8

echo
echo "  -- 查询值：应该各自看到自己的值 --"
for u in backend:backend-pass-123 frontend:frontend-pass-456; do
  echo -n "    $u 查到的值: "
  curl -s --max-time 30 -u "$u" \
    --data-urlencode 'query=l10_va_value' \
    'http://localhost:8427/api/v1/query' \
    | python3 -c 'import json,sys
d=json.load(sys.stdin); r=d.get("data",{}).get("result",[])
vals=sorted(set(x["value"][1] for x in r))
print(vals if r else "空")' 2>&1
done

echo
echo "  -- 直接绕过 vmauth 查后端，确认数据真的在不同租户 --"
echo -n "    tenant 100 (backend):  "
curl -s --max-time 30 --data-urlencode 'query=l10_va_value' \
  'http://localhost:8481/select/100/prometheus/api/v1/query' \
  | python3 -c 'import json,sys
d=json.load(sys.stdin); r=d.get("data",{}).get("result",[])
print(sorted(set(x["value"][1] for x in r)) if r else "空")' 2>&1
echo -n "    tenant 200 (frontend): "
curl -s --max-time 30 --data-urlencode 'query=l10_va_value' \
  'http://localhost:8481/select/200/prometheus/api/v1/query' \
  | python3 -c 'import json,sys
d=json.load(sys.stdin); r=d.get("data",{}).get("result",[])
print(sorted(set(x["value"][1] for x in r)) if r else "空")' 2>&1

echo
echo "  → 若 backend 只看到 100、frontend 只看到 200，"
echo "     说明 vmauth 成功把【认证身份 → 租户】绑定了"
