#!/bin/bash
# 课 1 复验：照抄讲义里的命令，逐条跑一遍（不补全、不绕过）
set -u
W=/mnt/d/projects/learning/kafka/kafka-python-client
NET=stage6-observability_kafka-net
IMG=python:3.12-slim

echo "########## 复验 A：讲义第二节 uv 环境流程 ##########"
docker run --rm --network "$NET" -v /mnt/d/projects/learning/kafka:/mnt/kafka "$IMG" \
  bash -c 'cd /mnt/kafka/kafka-python-client/assets/bench
    pip install -q uv >/dev/null 2>&1
    uv venv /tmp/l1-venv 2>&1 | tail -1
    export VIRTUAL_ENV=/tmp/l1-venv
    uv pip install -q kafka-python==3.0.11 confluent-kafka==2.15.1 aiokafka==0.14.0 2>&1 | tail -2
    /tmp/l1-venv/bin/python -c "import kafka,confluent_kafka,aiokafka; print(\"三库导入 OK:\", kafka.__version__, confluent_kafka.__version__, aiokafka.__version__)"'

echo ""
echo "########## 复验 B：讲义六层自检脚本 ##########"
docker run --rm --network "$NET" -v "$W/assets/bench:/w" "$IMG" \
  bash -c 'pip install -q kafka-python==3.0.11 >/dev/null 2>&1; python /w/verify_connectivity.py' 2>&1 | tail -20

echo ""
echo "########## 复验 C：讲义中的链接是否可达 ##########"
DOC="$W/stages/1-环境与选型/课1-三库生态与实操环境.md"
python3 - "$DOC" <<'PYEOF'
import os
import re
import sys

doc = sys.argv[1]
base = os.path.dirname(os.path.abspath(doc))
bad = []
with open(doc, encoding="utf-8") as f:
    for m in re.finditer(r"\[([^\]]*)\]\(([^)]+)\)", f.read()):
        target = m.group(2)
        if target.startswith(("http://", "https://", "#")):
            continue
        path = target.split("#")[0]
        if not path:
            continue
        full = os.path.normpath(os.path.join(base, path))
        if not os.path.exists(full):
            bad.append((target, full))
if bad:
    print("  断链:")
    for t, f in bad:
        print(f"    ✗ {t}  →  {f}")
else:
    print("  全部链接可达 ✓")
PYEOF
