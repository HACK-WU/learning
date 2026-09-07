#!/usr/bin/env bash
# 课 2 知识点 2.1 实验（第一段）：全新实例 + 默认口令的首次登录行为
# 目的：用「干净」的 Grafana 实测 —— 首次登录是否强制改密、health 接口返回什么
set -u

GF_NAME="gf-l02"
GF_PORT="3011"
NET="grafana-net"

echo "=== 0. 清掉上一轮残留 ==="
docker rm -f "$GF_NAME" >/dev/null 2>&1 && echo "  已删除旧容器" || echo "  无残留"

echo
echo "=== 1. 以『完全默认』启动（不挂卷、不设环境变量） ==="
docker run -d --name "$GF_NAME" --network "$NET" -p "${GF_PORT}:3000" \
  grafana/grafana:13.2.1 >/dev/null
echo "  容器已创建：$GF_NAME  ${GF_PORT}->3000"

echo
echo "=== 2. 等待就绪（判据：/api/health 里 database=ok） ==="
for i in $(seq 1 90); do
  body=$(curl -s "http://localhost:${GF_PORT}/api/health" 2>/dev/null)
  if echo "$body" | grep -q '"database":"ok"'; then
    echo "  第 ${i} 次探测就绪（约 $((i*2)) 秒）"
    echo "  返回：$body" | tr -d '\n'; echo
    break
  fi
  if [ "$i" = "90" ]; then echo "  ❌ 180 秒未就绪，最后返回：$body"; fi
  sleep 2
done

echo
echo "=== 3. 未登录时访问受保护接口 ==="
code=$(curl -s -o /tmp/l02_anon.txt -w '%{http_code}' "http://localhost:${GF_PORT}/api/datasources")
echo "  GET /api/datasources -> HTTP $code"
echo "  响应体：$(cat /tmp/l02_anon.txt)"

echo
echo "=== 4. 用默认口令 admin/admin 登录，观察响应 ==="
curl -s -c /tmp/l02_cookie.txt -X POST "http://localhost:${GF_PORT}/login" \
  -H 'Content-Type: application/json' \
  -d '{"user":"admin","password":"admin"}' -w '\n  HTTP %{http_code}\n'

echo
echo "=== 5. 登录后 GET /api/user（找『是否强制改密』的信号） ==="
curl -s -b /tmp/l02_cookie.txt "http://localhost:${GF_PORT}/api/user" -w '\n  HTTP %{http_code}\n'

echo
echo "=== 6. frontend settings 里与改密相关的字段 ==="
curl -s -b /tmp/l02_cookie.txt "http://localhost:${GF_PORT}/api/frontend/settings" \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print(json.dumps({k:v for k,v in d.items() if 'password' in k.lower() or 'change' in k.lower() or k in ('bootData','defaultDatasource','auth')}, ensure_ascii=False, indent=2))" 2>/dev/null || echo "  （解析失败，原样输出）"

echo
echo "=== 7. 默认密码未改时，改密接口的现状 ==="
curl -s -b /tmp/l02_cookie.txt -X PUT "http://localhost:${GF_PORT}/api/user/password" \
  -H 'Content-Type: application/json' \
  -d '{"oldPassword":"admin","newPassword":"lab-pass-2026","confirmNew":"lab-pass-2026"}' \
  -w '\n  HTTP %{http_code}\n'
