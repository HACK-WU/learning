#!/usr/bin/env bash
# 方案 A：把 webhook 接收端跑进 grafana-net，Grafana 用容器名访问
set -u
cd /mnt/d/projects/learning/grafana

echo "--- [1] 清理旧容器 ---"
docker rm -f l08-webhook 2>/dev/null | sed 's/^/  /'
echo "  done"

echo ""
echo "--- [2] 启动接收端容器（加入 grafana-net）---"
docker run -d --name l08-webhook --network grafana-net \
  -v /mnt/d/projects/learning/grafana/playground:/data \
  python:3.11-slim \
  python /data/l08_webhook_receiver.py 2>&1 | tail -2 | sed 's/^/  /'

sleep 4

echo ""
echo "--- [3] 容器状态 ---"
docker ps --format '{{.Names}} {{.Status}}' | grep -E 'l08-webhook' | sed 's/^/  /'

echo ""
echo "--- [4] 容器内自测 ---"
docker exec l08-webhook python -c "
import urllib.request
print(urllib.request.urlopen('http://127.0.0.1:9999/',timeout=5).read().decode())
" 2>&1 | sed 's/^/  /'

echo ""
echo "--- [5] 关键：Grafana 容器访问 l08-webhook:9999 ---"
code=$(docker exec grafana-lab sh -c "wget -q -O /dev/null -T 5 http://l08-webhook:9999/ 2>/dev/null; echo \$?")
echo "  wget exit=$code  (0=通)"

echo ""
echo "--- [6] 网络确认：两者是否同一网络 ---"
for c in grafana-lab l08-webhook; do
  echo -n "  $c: "
  docker inspect $c --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}'
done

echo ""
echo "--- [7] 日志文件应已创建（清空重建）---"
ls -la playground/l08-webhook-log.jsonl 2>&1 | sed 's/^/  /'
