#!/usr/bin/env bash
# 诊断：告警到底进没进 Alertmanager？为什么 webhook 没收到？
set -u
echo "=== 1. AM 上有没有这条告警？ ==="
for p in 19120 19121; do
  echo "  --- 端口 $p ---"
  curl -s "http://localhost:$p/api/v2/alerts" | python -c "
import sys,json
d=json.load(sys.stdin)
print(f'   告警数 = {len(d)}')
for a in d:
    print('   ', a.get('labels'), 'status=', a.get('status',{}).get('state'))
"
done

echo
echo "=== 2. AM 的日志（看有没有发送动作/报错）==="
docker logs l8-am-1 2>&1 | tail -n 15 | sed 's/^/   am-1: /'
echo
docker logs l8-am-2 2>&1 | tail -n 15 | sed 's/^/   am-2: /'

echo
echo "=== 3. webhook 容器是否在跑、网络是否通 ==="
docker ps --filter "name=l8-webhook" --format "   {{.Names}} {{.Status}}"
echo "   --- 从 am-1 容器内测试 webhook 连通性 ---"
docker exec l8-am-1 wget -qO- --timeout=3 http://l8-webhook:8080/count 2>&1 | sed 's/^/   /' || echo "   wget 不可用或连不通"

echo
echo "=== 4. webhook 容器日志（全部）==="
docker logs l8-webhook 2>&1 | tail -n 20 | sed 's/^/   /'
