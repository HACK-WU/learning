#!/bin/bash
# 用独立容器跑 capstone 服务，排除 l11 环境干扰
# 镜像用现成的 kafka-pybench:3.12-l11（不 build、不联网）
# 代码通过挂载宿主机目录（需 WSL 路径转换）
IMG=kafka-pybench:3.12-l11
NAME=capstone-svc
SRC=/mnt/d/projects/learning/kafka/kafka-python-client/capstone

echo "=== 清理旧容器 ==="
docker rm -f $NAME 2>/dev/null

echo "=== 启动独立容器 ==="
docker run -d --name $NAME \
  --network bench_kafka-net \
  -v "$SRC":/app/capstone \
  -e KAFKA_BROKERS=kafka-1:9092,kafka-2:9092,kafka-3:9092 \
  -e GROUP_ID=capstone-svc-clean \
  -e PYTHONPATH=/app \
  -e PYTHONUNBUFFERED=1 \
  -w /app/capstone \
  $IMG \
  /app/.venv/bin/python /app/.venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000

sleep 18
echo "=== 就绪检查 ==="
docker exec $NAME /app/.venv/bin/python -c "
import json,urllib.request,urllib.error
try:
    print('ready:',json.loads(urllib.request.urlopen('http://localhost:8000/ready',timeout=25).read().decode()))
except urllib.error.HTTPError as e:
    print('503:',e.read().decode()[:150])
s=json.loads(urllib.request.urlopen('http://localhost:8000/stats',timeout=20).read())
print('parts:',len(s.get('lag_by_partition',{})),'lag:',s.get('lag_total'))
"
