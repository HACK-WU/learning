#!/bin/bash
# 集群卫生检查（修正版）
#
# 为什么重写：
#   旧版用 kafka-topics.sh --list 2>/dev/null，但 JMX Exporter 端口冲突
#   会把 stdout 一起吞掉（课 5/6 复验连续两次误报"集群干净"）。
#   修正：改用客户端 API 列举，彻底绕开 CLI 的 JMX 污染。
set -u
B=/mnt/d/projects/learning/kafka/kafka-python-client/assets/bench

cat > /tmp/hygiene.py <<'PYEOF'
import socket
import sys
from kafka import KafkaAdminClient

BS = []
for h in ("kafka-1", "kafka-2", "kafka-3"):
    try:
        s = socket.socket(); s.settimeout(3)
        s.connect((socket.gethostbyname(h), 9092))
        BS.append(f"{h}:9092"); s.close()
    except OSError:
        pass
if not BS:
    print("  ✗ 三个 broker 全不可达"); sys.exit(1)

a = KafkaAdminClient(bootstrap_servers=",".join(BS), request_timeout_ms=15000)
all_t = sorted(a.list_topics())
sys_t = [t for t in all_t if t.startswith("__")]
course = [t for t in all_t if not t.startswith("__")]
print(f"  可达 broker: {len(BS)}/3   topic 总数: {len(all_t)} (系统 {len(sys_t)} / 业务 {len(course)})")
for t in course:
    print(f"    - {t}")
a.close()
PYEOF

docker run --rm --network stage6-observability_kafka-net \
  -v /tmp/hygiene.py:/h.py kafka-pybench:3.12 \
  /app/.venv/bin/python /h.py 2>&1 | grep -v -e 'rdkafka#' -e 'Unclosed'
