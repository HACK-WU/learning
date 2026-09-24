#!/bin/bash
# 课 6 复验：幂等配置 + PID 惰性 + 语义边界 + 链接 + 卫生
set -u
W=/mnt/d/projects/learning/kafka/kafka-python-client
NET=stage6-observability_kafka-net
IMG=python:3.12-slim
B=$W/assets/bench

echo "########## A：幂等八组配置复验 ##########"
docker run --rm --network "$NET" -v "$B:/w" "$IMG" \
  bash -c 'pip install -q kafka-python==3.0.11 >/dev/null 2>&1
    python /w/verify_idempotence_config.py' 2>&1 \
  | grep -v -e 'rdkafka#' -e 'Unclosed' -e 'ERROR:kafka.cluster' \
  | grep -E 'enable_idempotence|抛异常|^  \[' | head -24

echo ""
echo "########## B：PID 惰性初始化 + 跨会话复验 ##########"
docker run --rm --network "$NET" -v "$B:/w" "$IMG" \
  bash -c 'pip install -q kafka-python==3.0.11 >/dev/null 2>&1
    python /w/verify_idem_send.py' 2>&1 \
  | grep -v -e 'rdkafka#' -e 'Unclosed' \
  | grep -E '发送前|发送后|producer 实例|PID|非幂等|惰性'

echo ""
echo "########## C：语义边界复验（重复在消费侧） ##########"
docker run --rm --network "$NET" -v "$B:/w" "$IMG" \
  bash -c 'pip install -q kafka-python==3.0.11 >/dev/null 2>&1
    python /w/verify_semantics.py' 2>&1 \
  | grep -v -e 'rdkafka#' -e 'Unclosed' \
  | grep -E 'position=|完全相同|重复消费|topic 实际|isolation_level'

echo ""
echo "########## D：链接可达性 ##########"
DOC="$W/stages/2-理解层-协议与源码/课6-确认语义与幂等.md"
python3 - "$DOC" <<'PYEOF'
import os, re, sys
doc = sys.argv[1]; base = os.path.dirname(os.path.abspath(doc)); bad=[]
with open(doc, encoding="utf-8") as f:
    for m in re.finditer(r"\[([^\]]*)\]\(([^)]+)\)", f.read()):
        t=m.group(2)
        if t.startswith(("http://","https://","#")): continue
        p=t.split("#")[0]
        if not p: continue
        full=os.path.normpath(os.path.join(base,p))
        if not os.path.exists(full): bad.append((t,full))
print("  全部链接可达 OK" if not bad else "  断链:")
for t,f in bad: print(f"    X {t} -> {f}")
PYEOF

echo ""
echo "########## E：围栏/结构 ##########"
python3 - "$DOC" <<'PYEOF'
import sys
s=open(sys.argv[1],encoding="utf-8").read()
print(f"  mermaid 块: {s.count('```mermaid')}，围栏总数: {s.count('```')}（应偶数）")
PYEOF

echo ""
echo "########## F：集群残留 ##########"
docker exec l15-kafka-1 /opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server localhost:9092 --list 2>/dev/null \
  | grep -E 'l1-|l2-|l3-|l4-|l5-|l6-' || echo "  集群干净（无 l1~l6 残留）"
docker ps -a --filter name=l6 --format '{{.Names}}' 2>/dev/null | head -3 || true
