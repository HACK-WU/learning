#!/bin/bash
set -u
echo "=== 1. topic 列表（stdout 与 stderr 分开看） ==="
docker exec l15-kafka-1 /opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server localhost:9092 --list 2>/tmp/e.txt
echo "  [stdout 上方]  [stderr 前 3 行]:"
head -3 /tmp/e.txt 2>/dev/null || true
echo "  退出码: $?"

echo ""
echo "=== 2. 用 kafka-python-ng 从容器内列 topic（绕开 CLI 的 JMX 污染） ==="
cat > /tmp/lt.py <<'PYEOF'
from kafka import KafkaAdminClient
import socket
BS = []
for h in ("kafka-1", "kafka-2", "kafka-3"):
    try:
        s = socket.socket(); s.settimeout(3)
        s.connect((socket.gethostbyname(h), 9092)); BS.append(f"{h}:9092"); s.close()
    except OSError:
        pass
print(f"  brokers = {', '.join(BS)}")
a = KafkaAdminClient(bootstrap_servers=",".join(BS), request_timeout_ms=15000)
ts = a.list_topics()
print(f"  topic 数量 = {len(ts)}")
for t in sorted(ts)[:25]:
    print(f"    - {t}")
a.close()
PYEOF
docker run --rm --network stage6-observability_kafka-net \
  -v /tmp/lt.py:/lt.py kafka-pybench:3.12 \
  /app/.venv/bin/python /lt.py 2>&1 | grep -v -e 'rdkafka#' -e 'Unclosed' | head -32
