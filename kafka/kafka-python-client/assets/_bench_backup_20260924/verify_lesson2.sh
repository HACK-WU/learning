#!/bin/bash
# 课 2 复验：照抄讲义里的命令与链接
set -u
W=/mnt/d/projects/learning/kafka/kafka-python-client
NET=stage6-observability_kafka-net
IMG=python:3.12-slim

echo "########## 复验 A：讲义第二节 confluent 替代 API ##########"
docker run --rm --network "$NET" -v "$W/assets/bench:/w" "$IMG" \
  bash -c 'pip install -q kafka-python==3.0.11 confluent-kafka==2.15.1 aiokafka==0.14.0 >/dev/null 2>&1
    python /w/verify_api_mapping.py' 2>&1 | grep -v 'rdkafka#\|Unclosed\|producer:' | tail -22

echo ""
echo "########## 复验 B：讲义第四节 默认值核验（v5 最终版） ##########"
docker run --rm -v "$W/assets/bench:/w" "$IMG" \
  bash -c 'pip install -q kafka-python==3.0.11 confluent-kafka==2.15.1 aiokafka==0.14.0 >/dev/null 2>&1
    python /w/verify_defaults5.py' 2>&1 | grep -v 'rdkafka#\|Unclosed\|producer:' | tail -20

echo ""
echo "########## 复验 C：讲义第五节 版本兼容矩阵 ##########"
docker run --rm --network "$NET" -v "$W/assets/bench:/w" "$IMG" \
  bash -c 'pip install -q kafka-python==3.0.11 confluent-kafka==2.15.1 aiokafka==0.14.0 >/dev/null 2>&1
    python /w/verify_compat_matrix.py' 2>&1 | grep -v 'rdkafka#\|Unclosed\|producer:' | tail -12

echo ""
echo "########## 复验 D：链接可达性 ##########"
DOC="$W/stages/1-环境与选型/课2-三库横评与API对照.md"
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
        print(f"    X {t}  ->  {f}")
else:
    print("  全部链接可达 OK")
PYEOF
