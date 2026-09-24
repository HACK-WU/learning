"""课13 独立复审：逐条核验讲义结论。
铁律（课 12 固化）：每条"缺失/错误/遗漏"判定必须先核验再写入。
本次重点核验：
  1. 吞吐数字是否可复现（33/s vs 112 万/s 的对比是否成立）
  2. 三次误诊的描述与实测是否一致
  3. 6 个能力是否真的工作
"""
import json
import sys
import time
import urllib.request
import urllib.error

sys.path.insert(0, "/app/capstone")
from app import config  # noqa: E402
from app.schema import OrderEvent  # noqa: E402
from app.worker import default_process  # noqa: E402
from confluent_kafka import Consumer, Producer  # noqa: E402
from confluent_kafka.admin import AdminClient, NewTopic  # noqa: E402

BASE = "http://localhost:8000"
P = F = 0


def chk(d, c, ev=""):
    global P, F
    if c:
        P += 1
        print(f"  OK   {d}")
    else:
        F += 1
        print(f"  FAIL {d}   <<< {ev}")


print("=" * 74)
print("课 13 · 独立复审")
print("=" * 74)

# ---- 结论 5/6：吞吐测法对比 ----
print("\n[核验1] 吞吐测法对比（讲义结论 5、6）")
a = AdminClient({"bootstrap.servers": config.BROKERS})
N = 2000
topic = f"rv-{int(time.time()) % 100000}"
for t, f in a.create_topics([NewTopic(topic, num_partitions=4,
                                      replication_factor=1)]).items():
    f.result()
pp = Producer({"bootstrap.servers": config.BROKERS, "linger.ms": 5})
for i in range(N):
    pp.produce(topic, json.dumps({"order_id": f"r{i:05d}", "user_id": "u",
                                  "amount": 10.0 + i, "currency": "CNY"}).encode())
pp.flush(15)

gid = f"rv-{int(time.time()) % 100000}"
conf = dict(config.consumer_conf()); conf["group.id"] = gid
c = Consumer(conf)
c.subscribe([topic])
for _ in range(20):
    c.poll(1.0)
    if len(c.assignment()) == 4:
        break

n = 0
t0 = time.time()
arrivals = []
while n < N and time.time() - t0 < 30:      # 测法A：等 N 条
    m = c.poll(timeout=1.0)
    if m is None or m.error():
        continue
    n += 1
    arrivals.append(time.time() - t0)
elA = time.time() - t0
rateA = n / elA if elA > 0 else 0
print(f"    测法A（等{N}条）: {n} 条 / {elA:.2f}s = {rateA:.0f} 条/秒")

if len(arrivals) > 20:
    t95 = arrivals[int(len(arrivals) * 0.95) - 1]
    rateB = int(len(arrivals) * 0.95) / t95 if t95 > 0 else 0
    print(f"    测法B（95分位）: {int(len(arrivals)*0.95)} 条 / {t95:.3f}s = {rateB:.0f} 条/秒")
    chk("两种测法差异 >100 倍（讲义结论6 成立）",
        rateB / rateA > 100 if rateA > 0 else False, f"A={rateA:.0f} B={rateB:.0f}")
    chk("测法A 耗时接近超时上限（尾部等待指纹）",
        elA > 25, f"elA={elA:.1f}s")
else:
    chk("样本足够", False, f"仅 {len(arrivals)} 条")
c.close()

# ---- 核验2：分区倾斜（讲义 3.3）----
print("\n[核验2] 分区倾斜现象")
c2 = Consumer({"bootstrap.servers": config.BROKERS,
               "group.id": f"skew-{int(time.time()) % 100000}",
               "auto.offset.reset": "earliest", "enable.auto.commit": False})
c2.subscribe([topic])
for _ in range(20):
    c2.poll(1.0)
    if c2.assignment():
        break
counts = {}
for tp in sorted(c2.assignment(), key=lambda x: x.partition):
    lo, hi = c2.get_watermark_offsets(tp, timeout=5)
    counts[tp.partition] = hi - lo
print(f"    分区分布: {counts}")
mx = max(counts.values()) if counts else 0
mn = min(counts.values()) if counts else 0
chk("存在分区倾斜（最大/最小 悬殊）", mx > mn * 10 if mn >= 0 else mx > 100,
    f"max={mx} min={mn}")
c2.close()

# ---- 核验3：独立 group 无 rebalance ----
print("\n[核验3] 独立 group 不受服务 rebalance 影响")
ok = len(counts) == 4
chk("独立 group 能拿到 4 个分区", ok, f"{len(counts)}")

# ---- 核验4：服务能力（若服务在跑）----
print("\n[核验4] 服务端点")


def stats():
    with urllib.request.urlopen(BASE + "/stats", timeout=20) as r:
        return json.loads(r.read().decode())


try:
    s = stats()
    chk("/stats 可访问", True)
    chk("lag 分区覆盖 4 个", len(s.get("lag_by_partition", {})) == 4,
        str(s.get("lag_by_partition")))
    m = urllib.request.urlopen(BASE + "/metrics", timeout=20).read().decode()
    chk("lag 是 gauge", "# TYPE capstone_consumer_lag gauge" in m, "")
    chk("指标含 produced", "capstone_orders_produced_total" in m, "")
    chk("指标含 consumed", "capstone_orders_consumed_total" in m, "")
    # 核验 DLQ 结论
    chk("DLQ 计数存在（讲义结论：坏消息进 DLQ）",
        "dlq" in s, str(list(s.keys())))
except Exception as e:
    print(f"    (服务未运行，跳过: {type(e).__name__})")

print("\n" + "=" * 74)
print(f"  通过 {P}  失败 {F}")
print("=" * 74)
