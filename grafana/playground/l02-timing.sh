#!/usr/bin/env bash
# 分离两个变量：A) 真实就绪耗时  B) grep 格式陷阱
# 课 1 曾把「探测失败」归因于「装插件慢 60 秒」，本脚本验证该归因是否成立
set -u
NAME="gf-l02b"
PORT="3012"
NET="grafana-net"

echo "=== 0. 清理 ==="
docker rm -f "$NAME" >/dev/null 2>&1 && echo "  已删旧容器" || echo "  无残留"

echo
echo "=== 1. 记录启动时刻 ==="
T0=$(date +%s)
docker run -d --name "$NAME" --network "$NET" -p "${PORT}:3000" \
  grafana/grafana:13.2.1 >/dev/null
echo "  启动于 $(date -d @$T0 +%T)"

echo
echo "=== 2. 逐秒探测：HTTP 状态码 / 紧凑写法 / 缩进写法，三者分开记 ==="
READY_AT="-"
for i in $(seq 1 120); do
  body=$(curl -s "http://localhost:${PORT}/api/health" 2>/dev/null)
  code=$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:${PORT}/api/health" 2>/dev/null)
  compact="NO"; spaced="NO"
  echo "$body" | grep -q '"database":"ok"'     && compact="YES"
  echo "$body" | grep -q '"database": "ok"'    && spaced="YES"
  if [ "$spaced" = "YES" ]; then
    READY_AT="$(( $(date +%s) - T0 ))"
    echo "  t+${READY_AT}s  测到第 ${i} 次：HTTP=$code  紧凑写法=$compact  缩进写法=$spaced  ← 就绪"
    break
  fi
  if [ $((i % 5)) = 0 ]; then
    echo "  t+$(( $(date +%s) - T0 ))s  第 ${i} 次：HTTP=$code  紧凑=$compact  缩进=$spaced"
  fi
  sleep 1
done

echo
echo "=== 3. 结论 ==="
echo "  真实就绪耗时：${READY_AT} 秒"
echo "  紧凑写法能否命中：$(curl -s "http://localhost:${PORT}/api/health" | grep -q '"database":"ok"' && echo 能 || echo 不能)"
echo "  缩进写法能否命中：$(curl -s "http://localhost:${PORT}/api/health" | grep -q '"database": "ok"' && echo 能 || echo 不能)"

echo
echo "=== 4. 启动日志里与插件安装相关的行 ==="
docker logs "$NAME" 2>&1 | grep -iE 'plugin|install|download|app update' | head -20

echo
echo "=== 5. 已装插件清单 ==="
docker exec "$NAME" ls /var/lib/grafana/plugins 2>/dev/null || echo "  （无法列出）"
