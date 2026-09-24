#!/bin/bash
# 课 4 复验：源码结论 + 实测结论 + 链接 + 集群卫生
set -u
W=/mnt/d/projects/learning/kafka/kafka-python-client
NET=stage6-observability_kafka-net
IMG=python:3.12-slim
B=$W/assets/bench

echo "########## A：背压结论复验（核心） ##########"
docker run --rm --network "$NET" -v "$B:/w" "$IMG" \
  bash -c 'pip install -q kafka-python==3.0.11 >/dev/null 2>&1
    python /w/verify_backpressure.py' 2>&1 | grep -v -e 'rdkafka#' -e 'Unclosed' \
  | grep -E 'ValueError|RSS|→|✓|✗|用时'

echo ""
echo "########## B：全包搜 BufferPool（证明不存在） ##########"
docker run --rm -v "$B:/w" "$IMG" \
  bash -c 'pip install -q kafka-python==3.0.11 >/dev/null 2>&1
    python /w/dump_backpressure3.py' 2>&1 | grep -v -e 'rdkafka#' -e 'Unclosed' \
  | grep -A4 '整个 kafka 包搜'

echo ""
echo "########## C：acks rf=3 反转复验 ##########"
docker run --rm --network "$NET" -v "$B:/w" "$IMG" \
  bash -c 'pip install -q kafka-python==3.0.11 >/dev/null 2>&1
    python /w/verify_acks_rf3.py' 2>&1 | grep -v -e 'rdkafka#' -e 'Unclosed' \
  | grep -E 'isr=|acks |慢 |error_code'

echo ""
echo "########## D：链接可达性 ##########"
DOC="$W/stages/2-理解层-协议与源码/课4-生产者内部机制.md"
python3 - "$DOC" <<'PYEOF'
import os, re, sys
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
echo "########## E：mermaid 块数量 ##########"
python3 - "$DOC" <<'PYEOF'
import re, sys
s = open(sys.argv[1], encoding="utf-8").read()
print(f"  mermaid 块: {s.count('```mermaid')}，围栏总数: {s.count('```')}（应为偶数）")
PYEOF

echo ""
echo "########## F：集群残留 ##########"
docker exec l15-kafka-1 /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --list 2>/dev/null \
  | grep -E 'l1-|l2-|l3-|l4-' || echo "  集群干净（无 l1-/l2-/l3-/l4- 残留）"
