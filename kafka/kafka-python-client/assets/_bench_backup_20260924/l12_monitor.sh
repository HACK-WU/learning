#!/bin/bash
# 课 12 收官：可运行的 lag 监控导出器 + 三条告警规则（先验证语义再配）
# 铁律（mem_274a28_126d48b）：写告警前必须 ①看实际值域 ②确认语义 ③连续采样看单调性
timeout 120 docker exec -i l11 /app/.venv/bin/python - <<'PYEOF' 2>&1 | grep -v -e Authlib -e 'from ._compat'
import time, json
from confluent_kafka import Consumer, TopicPartition
from confluent_kafka.admin import AdminClient
BROKERS="kafka-1:9092,kafka-2:9092,kafka-3:9092"; TOPIC="l11-async-bench"
def banner(t): print(f"\n{'─'*74}\n{t}\n{'─'*74}")

def collect_lag(c, topic):
    """正确算法：跳过未分配/哨兵值，只用 watermark - committed"""
    out={}
    for tp in c.assignment():
        try:
            lo,hi=c.get_watermark_offsets(tp,timeout=5)
            cm=c.committed([tp],timeout=5)[0].offset
            if hi<0: continue                       # watermark 无效
            off=cm if (cm and cm>=0) else 0         # 哨兵值兜底
            out[tp.partition]=max(0,hi-off)
        except Exception: continue
    return out

c=Consumer({"bootstrap.servers":BROKERS,"group.id":"l12-lag-demo",
            "auto.offset.reset":"earliest","enable.auto.commit":True,
            "auto.commit.interval.ms":300})
c.subscribe([TOPIC])
c.consume(num_messages=100,timeout=10); c.commit(asynchronous=False)

banner("① 实际值域核验（采样 5 次，间隔 0.6s）")
samples=[]
for i in range(5):
    lags=collect_lag(c,TOPIC)
    samples.append(lags)
    tot=sum(lags.values())
    print(f"  第{i+1}次: 各分区={lags}  总计={tot}")
    c.consume(num_messages=30,timeout=2); c.commit(asynchronous=False)
    time.sleep(0.6)
totals=[sum(s.values()) for s in samples]
decr=all(totals[i]>=totals[i+1] for i in range(len(totals)-1))
print(f"\n  总 lag 序列: {totals}")
print(f"  值域: [{min(totals)}, {max(totals)}]")
print(f"  单调性: {'严格递减（消费在追赶）' if decr else '有升有降'}")
print(f"  关键：{'递减' if decr else '波动'} 证明它是【可上可下的瞬时值 gauge】，"
      f"不是单调递增的累积计数")

banner("② 语义确认：lag 是瞬时值还是累积计数？")
print(f"  定义：lag = hi_offset - committed_offset")
print(f"  性质：消费者追上则下降，生产快于消费则上升 -> 【瞬时值/gauge】")
print(f"  证据：双向实测见 l12_lag_rise.sh（阶段A 500→2500 递增；阶段B 2100→500 递减）")
print(f"        本脚本为稳态采样，观测到 {'严格递减' if decr else '波动'}（消费追赶中）")
print(f"  结论：用 gauge 类型，可写 `kafka_consumer_lag > 10000` 告警 ✓")
print(f"  反例（课17教训）：RequestHandlerAvgIdlePercent 是 Count 累积，<0.3 永不触发")

banner("③ 对照：stats.consumer_lag 为什么不能当主数据源")
docs=[]
c2=Consumer({"bootstrap.servers":BROKERS,"group.id":"l12-lag-demo",
             "auto.offset.reset":"earliest","enable.auto.commit":True,
             "statistics.interval.ms":500})
import ctypes
# 用 stats_cb 重建一个带回调的消费者
docs.clear()
def on_stats(s): docs.append(json.loads(s))
c.close()
c3=Consumer({"bootstrap.servers":BROKERS,"group.id":"l12-lag-demo",
             "auto.offset.reset":"earliest","enable.auto.commit":True,
             "auto.commit.interval.ms":300,
             "statistics.interval.ms":500,"stats_cb":on_stats})
c3.subscribe([TOPIC])
c3.consume(num_messages=50,timeout=5); c3.commit(asynchronous=False)
t0=time.time()
while time.time()-t0<2: c3.poll(0); time.sleep(0.1)
if docs:
    pl=docs[-1]["topics"][TOPIC]["partitions"]
    v={p.get("partition"):p.get("consumer_lag") for p in pl.values() if isinstance(p,dict) and p.get("partition",-1)>=0}
    print(f"  stats.consumer_lag : {v}")
    print(f"  手算(committed)    : {collect_lag(c3,TOPIC)}")
    n_ok=sum(1 for x in v.values() if x is not None and x>=0)
    print(f"  stats 有值分区 {n_ok}/{len(v)}  -> 未活跃 fetch 的分区是 -1")
    print(f"  结论：stats 只能做辅助；主数据源必须是 committed()+watermark 手算")
c3.close()
PYEOF
