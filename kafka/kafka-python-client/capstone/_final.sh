#!/bin/bash
echo "=== 最终 topic 状态 ==="
docker exec l11 /app/.venv/bin/python -c '
from confluent_kafka.admin import AdminClient
a = AdminClient({"bootstrap.servers": "kafka-1:9092,kafka-2:9092,kafka-3:9092"})
ts = sorted(a.list_topics(timeout=10).topics)
print("  集群 topic 总数:", len(ts))
for t in ts:
    print("   ", t)
'
echo
echo "=== capstone 容器状态 ==="
docker ps --format '{{.Names}}\t{{.Status}}' | grep -i capstone-svc
echo
echo "=== 服务端点 ==="
docker exec capstone-svc /app/.venv/bin/python -c '
import json, urllib.request, urllib.error
for p in ("/health", "/ready", "/stats"):
    try:
        d = json.loads(urllib.request.urlopen("http://localhost:8000"+p, timeout=20).read())
        print(f"  {p}: {json.dumps(d, ensure_ascii=False)[:180]}")
    except urllib.error.HTTPError as e:
        print(f"  {p}: HTTP {e.code}")
    except Exception as e:
        print(f"  {p}: {type(e).__name__}")
'
