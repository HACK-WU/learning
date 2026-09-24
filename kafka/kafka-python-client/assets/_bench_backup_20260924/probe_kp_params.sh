#!/bin/bash
set -u
cat > /tmp/p.py <<'PYEOF'
from kafka import KafkaProducer
D = KafkaProducer.DEFAULT_CONFIG
print("=== kafka-python 3.0.11 全部含 memory/buffer/max 的配置键 ===")
for k in sorted(D):
    kl = k.lower()
    if any(w in kl for w in ("memory", "buffer", "max_block", "max_request", "batch")):
        print(f"  {k:<45} = {D[k]!r}")
PYEOF
docker run --rm -v /tmp/p.py:/p.py kafka-pybench:3.12 \
  /app/.venv/bin/python /p.py 2>&1 | grep -v -e 'rdkafka#' -e 'Unclosed'
