#!/bin/bash
# 清理课 4/5 残留 topic（执行删除，需用户授权）
#
# 为什么这些残留没被早发现：
#   旧卫生检查用 kafka-topics.sh --list 2>/dev/null，JMX Exporter 端口冲突
#   把 stdout 一起吞掉 → grep 拿空输入 → 误判"集群干净"（课 5/6 连骗两次）。
#   现在改用客户端 API 列举。
set -u

cat > /tmp/clean.py <<'PYEOF'
import socket
import sys
from kafka import KafkaAdminClient
from kafka.errors import UnknownTopicOrPartitionError

BS = []
for h in ("kafka-1", "kafka-2", "kafka-3"):
    try:
        s = socket.socket(); s.settimeout(3)
        s.connect((socket.gethostbyname(h), 9092))
        BS.append(f"{h}:9092"); s.close()
    except OSError:
        pass

a = KafkaAdminClient(bootstrap_servers=",".join(BS), request_timeout_ms=20000)
all_t = sorted(a.list_topics())

# 只删课程验证用的临时 topic；系统 topic 与非课程 topic 一律不动
COURSE_PREFIXES = (
    "l1-", "l2-", "l3-", "l4-", "l5-", "l6-",
    "l7-", "l8-", "l9-", "l10-",
    "bench-", "diag-", "slow-", "sz-",
)
doomed = [t for t in all_t if t.startswith(COURSE_PREFIXES)]
keep = [t for t in all_t if t not in doomed]

print(f"  待删除 [{len(doomed)}]:")
for t in doomed:
    print(f"    - {t}")
print(f"  保留 [{len(keep)}]:")
for t in keep:
    print(f"    + {t}")

if doomed:
    try:
        a.delete_topics(doomed, timeout_ms=30000)
        print(f"\n  已提交删除：{len(doomed)} 个")
    except Exception as e:
        print(f"\n  删除失败: {type(e).__name__}: {e}")
        sys.exit(1)
a.close()
PYEOF

docker run --rm --network stage6-observability_kafka-net \
  -v /tmp/clean.py:/c.py kafka-pybench:3.12 \
  /app/.venv/bin/python /c.py 2>&1 | grep -v -e 'rdkafka#' -e 'Unclosed'

echo ""
echo "=== 删除后复查 ==="
sleep 3
bash /mnt/d/projects/learning/kafka/kafka-python-client/assets/bench/check_hygiene.sh 2>&1
