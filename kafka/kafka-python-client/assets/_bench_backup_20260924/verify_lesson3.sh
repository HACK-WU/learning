#!/bin/bash
# 课 3 复验：照抄讲义命令 + 链接校验
set -u
W=/mnt/d/projects/learning/kafka/kafka-python-client
NET=stage6-observability_kafka-net
IMG=python:3.12-slim
B=$W/assets/bench

echo "########## 复验 A：第一节 aiokafka AdminClient ##########"
docker run --rm -v "$B:/w" "$IMG" \
  bash -c 'pip install -q aiokafka==0.14.0 confluent-kafka==2.15.1 >/dev/null 2>&1
    python /w/verify_aiokafka_admin.py' 2>&1 | grep -v -e 'rdkafka#' -e 'Unclosed' | tail -8

echo ""
echo "########## 复验 B：第二节 返回结构 + Topic 生命周期 ##########"
docker run --rm --network "$NET" -v "$B:/w" "$IMG" \
  bash -c 'pip install -q kafka-python==3.0.11 >/dev/null 2>&1
    python /w/verify_admin_shapes.py' 2>&1 | grep -v -e 'rdkafka#' -e 'Unclosed' | grep -E 'type =|值   =|键:|✗|✓|error_code' | head -14

echo ""
echo "########## 复验 C：第三节 lag 计算 ##########"
docker run --rm --network "$NET" -v "$B:/w" "$IMG" \
  bash -c 'pip install -q kafka-python==3.0.11 confluent-kafka==2.15.1 >/dev/null 2>&1
    python /w/verify_consumer_group2.py' 2>&1 | grep -v -e 'rdkafka#' -e 'Unclosed' -e '%7|' | tail -12

echo ""
echo "########## 复验 D：链接可达性 ##########"
DOC="$W/stages/1-环境与选型/课3-AdminClient与元数据治理.md"
python3 - "$DOC" <<'PYEOF'
import os
import re
import sys

doc = sys.argv[1]
base = os.path.dirname(os.path.abspath(doc))
bad = []
with open(doc, encoding="utf-8") as f:
    for m in re.finditer(r"\[([^\]]*)\]\(([^)]+)\)", f.read()):
        t = m.group(2)
        if t.startswith(("http://", "https://", "#")):
            continue
        p = t.split("#")[0]
        if not p:
            continue
        full = os.path.normpath(os.path.join(base, p))
        if not os.path.exists(full):
            bad.append((t, full))
if bad:
    print("  断链:")
    for t, f in bad:
        print(f"    X {t}  ->  {f}")
else:
    print("  全部链接可达 OK")
PYEOF

echo ""
echo "########## 复验 E：集群残留检查 ##########"
docker exec l15-kafka-1 /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --list 2>/dev/null \
  | grep -E 'l1-|l2-|l3-' || echo "  集群干净（无 l1-/l2-/l3- 残留）"
