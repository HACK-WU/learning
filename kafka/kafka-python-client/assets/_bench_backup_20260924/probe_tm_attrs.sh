#!/bin/bash
set -u
cat > /tmp/sa.py <<'PYEOF'
import kafka.producer.transaction_manager as tm
print("=== TransactionManager 实例属性候选 ===")
import re
src = open(tm.__file__).read()
attrs = sorted(set(re.findall(r'self\.(_[a-z_]*(?:state|transition)[a-z_]*)', src)))
for a in attrs:
    print(f"  {a}")

print("\n=== TransactionState 全部状态 ===")
from kafka.producer.transaction_manager import TransactionState
for s in TransactionState:
    print(f"  {s}")

print("\n=== _transition_to 源码节选（含 READY/COMMITTING 判断）===")
import inspect
src2 = inspect.getsource(tm.TransactionManager._transition_to)
print(src2[:1800])
PYEOF
docker run --rm -v /tmp/sa.py:/a.py kafka-pybench:3.12 \
  /app/.venv/bin/python /a.py 2>&1 | grep -v -e 'rdkafka#' -e 'Unclosed' | head -45
