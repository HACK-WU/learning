#!/bin/bash
# 启动最小 SR 原型并冒烟测试
set -u
docker rm -f l9-minisr >/dev/null 2>&1
bash /mnt/d/projects/learning/kafka/kafka-python-client/assets/bench/l9_mini_sr.py.sh >/dev/null 2>&1
docker run -d --network bench_kafka-net --name l9-minisr \
  -v /tmp/mini_sr.py:/m.py kafka-pybench:3.12 \
  /app/.venv/bin/python /m.py >/dev/null 2>&1
sleep 5
echo "=== 容器状态 ==="
docker ps --format '{{.Names}}|{{.Status}}' | grep minisr
echo "=== 冒烟: GET /subjects ==="
docker exec l9-minisr /app/.venv/bin/python -c "
import urllib.request
print(urllib.request.urlopen('http://localhost:8081/subjects').read().decode())
"
