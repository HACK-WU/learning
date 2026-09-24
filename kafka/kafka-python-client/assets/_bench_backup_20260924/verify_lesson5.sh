#!/bin/bash
# 课 5 复验：位移双轨 + 再均衡收敛 + 链接 + 集群卫生
set -u
W=/mnt/d/projects/learning/kafka/kafka-python-client
NET=stage6-observability_kafka-net
IMG=python:3.12-slim
B=$W/assets/bench

echo "########## A：位移双轨结论复验（核心） ##########"
docker run --rm --network "$NET" -v "$B:/w" "$IMG" \
  bash -c 'pip install -q kafka-python==3.0.11 >/dev/null 2>&1
    python /w/verify_commit_path.py' 2>&1 | grep -v -e 'rdkafka#' -e 'Unclosed' \
  | grep -E 'position|committed|重放|消费到|→'

echo ""
echo "########## B：再均衡独立进程收敛复验 ##########"
docker run --rm --network "$NET" -v "$B:/w" "$IMG" \
  bash -c 'pip install -q kafka-python==3.0.11 >/dev/null 2>&1
python - <<PY
import socket, time
from kafka import KafkaAdminClient, KafkaProducer
from kafka.admin import NewTopic
BS=[]
for h in ["kafka-1","kafka-2","kafka-3"]:
    try:
        ip=socket.gethostbyname(h); s=socket.socket(); s.settimeout(3)
        s.connect((ip,9092)); BS.append(f"{h}:9092"); s.close()
    except OSError: pass
BS=",".join(BS)
a=KafkaAdminClient(bootstrap_servers=BS, request_timeout_ms=15000)
try:
    r=a.create_topics([NewTopic("l5-verify", num_partitions=4, replication_factor=1)])
    print("create:", [(x.get("name"), x.get("error_code")) for x in r.get("topics",[])])
except Exception as e: print("create:", type(e).__name__, str(e)[:60])
time.sleep(1)
p=KafkaProducer(bootstrap_servers=BS, max_block_ms=15000, acks=1)
for i in range(40): p.send("l5-verify", f"v-{i:02d}".encode())
p.flush(timeout=20); p.close()
from kafka import KafkaConsumer
cs=[]
for i in range(4):
    c=KafkaConsumer(bootstrap_servers=BS, group_id="l5-verify-g",
        auto_offset_reset="earliest", enable_auto_commit=False,
        session_timeout_ms=45000, heartbeat_interval_ms=3000, client_id=f"v{i}")
    c.subscribe(["l5-verify"]); cs.append(c)
    for _ in range(5):
        for x in cs: x.poll(timeout_ms=1000, max_records=1)
        time.sleep(0.4)
res=[tuple(sorted(tp.partition for tp in c.assignment())) for c in cs]
print("4 消费者分配:", res)
flat=[p for r in res for p in r]
print(f"合计 {len(flat)} 分区，无重叠: {len(set(flat))==4}")
for c in cs: c.close()
a.delete_topics(["l5-verify"]); a.close()
PY' 2>&1 | grep -v -e 'rdkafka#' -e 'Unclosed'

echo ""
echo "########## C：链接可达性 ##########"
DOC="$W/stages/2-理解层-协议与源码/课5-消费者内部机制.md"
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
echo "########## D：围栏/结构 ##########"
python3 - "$DOC" <<'PYEOF'
import sys
s=open(sys.argv[1],encoding="utf-8").read()
print(f"  mermaid 块: {s.count('```mermaid')}，围栏总数: {s.count('```')}（应偶数）")
PYEOF

echo ""
echo "########## E：集群残留 ##########"
docker exec l15-kafka-1 /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --list 2>/dev/null \
  | grep -E 'l1-|l2-|l3-|l4-|l5-' || echo "  集群干净（无 l1~l5 残留）"
echo "  残留容器:"; docker ps -a --filter name=l5c --format '{{.Names}}' 2>/dev/null || true
