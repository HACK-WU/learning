#!/bin/bash
set -u
cat > /tmp/sg.py <<'PYEOF'
import inspect, kafka
from kafka import KafkaProducer
P = KafkaProducer
print("=== kafka-python 3.0.11 事务方法真实签名 ===")
for m in ("init_transactions","begin_transaction","commit_transaction",
          "abort_transaction","send_offsets_to_transaction"):
    f = getattr(P, m, None)
    if f is None: continue
    try:
        sig = inspect.signature(f)
    except Exception as e:
        sig = f"<{e}>"
    print(f"  {m}{sig}")
    doc = (inspect.getdoc(f) or "").strip().split("\n")
    if doc and doc[0]:
        print(f"      doc: {doc[0][:110]}")

print("\n=== 源码定位 ===")
import kafka.producer.kafka as kpk
print(f"  模块文件: {kpk.__file__}")
import os
src = inspect.getsource(P.init_transactions)
print("\n--- init_transactions 源码 ---")
print(src)
PYEOF
docker run --rm -v /tmp/sg.py:/s.py kafka-pybench:3.12 \
  /app/.venv/bin/python /s.py 2>&1 | grep -v -e 'rdkafka#' -e 'Unclosed' | head -45
