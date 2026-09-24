#!/bin/bash
# 深挖：stats 字段全集 + lag 正确算法验证 + 关键指标语义核验
# 铁律（mem_274a28_126d48b）：先确认语义和值域，再谈告警
set -u
cat > /tmp/l12_p2.py <<'PYEOF'
import json, time
from confluent_kafka import Producer, Consumer, TopicPartition
BROKERS="kafka-1:9092,kafka-2:9092,kafka-3:9092"; TOPIC="l11-async-bench"
def banner(t): print(f"\n{'─'*74}\n{t}\n{'─'*74}")

# ═══ 1. broker 33 字段全解 ═══
banner("1. 单 broker 完整字段（生产/消费健康度看这些）")
doc={"d":None}
def on_stats(s):
    if doc["d"] is None: doc["d"]=json.loads(s)
p=Producer({"bootstrap.servers":BROKERS,"statistics.interval.ms":500,"stats_cb":on_stats})
p.produce(TOPIC,b"x"); p.flush(10)
for _ in range(40):                 # 最多等 4s，轮询触发
    if doc["d"] is not None: break
    p.poll(0); time.sleep(0.1)
assert doc["d"] is not None, "stats 回调未触发（interval 未到或 client 已关）"
b=list(doc["d"]["brokers"].values())[0]
KEY={"rtt":"往返延迟(微秒)","outbuf_cnt":"待发送缓冲区消息数","waitresp_cnt":"已发未回响应数",
     "tx":"发送请求数(累积)","txbytes":"发送字节(累积)","rx":"接收响应数(累积)",
     "rxbytes":"接收字节(累积)","txerrs":"发送错误(累积)","rxerrs":"接收错误(累积)",
     "state":"连接状态","connects":"连接次数","disconnects":"断开次数","throttle":"限速(微秒)"}
print(f"  {'字段':<18}{'值':>14}   含义")
for k in sorted(b.keys()):
    if not isinstance(b[k],(int,float,str)): continue
    print(f"  {k:<18}{str(b[k]):>14}   {KEY.get(k,'')}")

# ═══ 2. topics 层级（每分区 lag 就在里面）═══
banner("2. topics 层级：客户端自算 lag 的现成字段")
t=doc["d"]["topics"].get(TOPIC,{})
print(f"  topic 级字段: {[k for k in t.keys() if k!='partitions']}")
ps=t.get("partitions",{})
if ps:
    p0=list(ps.values())[0]
    print(f"  单分区字段: {sorted(p0.keys())}")
    for k in ["lo_offset","hi_offset","ls_offset","committed_offset","app_offset","stored_offset","consumer_lag"]:
        if k in p0: print(f"    {k:<20}= {p0[k]}")

# ═══ 3. lag 正确算法：对比三途径 ═══
banner("3. lag 算法核验：committed=-1001 哨兵值处理")
c=Consumer({"bootstrap.servers":BROKERS,"group.id":f"l12-dig-{int(time.time())%100000}",
            "auto.offset.reset":"earliest","enable.auto.commit":True})
parts=[TopicPartition(TOPIC,i) for i in range(4)]
c.assign(parts)
c.consume(num_messages=10,timeout=5)
c.commit(asynchronous=False)          # 先提交一次，让 committed 有真实值
time.sleep(0.5)
print(f"  {'分区':<6}{'lo':>8}{'hi':>8}{'committed':>12}{'position':>10}{'lag(算)':>10}")
tot=0
for tp in parts:
    lo,hi=c.get_watermark_offsets(tp,timeout=10)
    cm=c.committed([tp],timeout=10)[0].offset
    po=c.position([tp])[0].offset
    safe=cm if cm>=0 else 0                      # ← 关键：哨兵值兜底
    lag=max(0,hi-safe); tot+=lag
    print(f"  {tp.partition:<6}{lo:>8}{hi:>8}{cm:>12}{po:>10}{lag:>10}")
print(f"  总 lag = {tot}")
print(f"\n  铁律验证：committed 可能为 -1001（未提交）")
print(f"            直接 hi - (-1001) = {hi+1001}  -> 假告警")
print(f"            正确：offset<0 兜底为 0      -> lag={max(0,hi-0)}")
c.close()
PYEOF
docker cp /tmp/l12_p2.py l11:/p2.py >/dev/null
docker exec l11 /app/.venv/bin/python /p2.py 2>&1 \
  | grep -v -e Authlib -e 'from ._compat' | head -70
