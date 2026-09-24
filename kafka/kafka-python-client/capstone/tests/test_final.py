"""课13 最终验收：干净环境下逐条验证 6 个核心能力 + 真实吞吐。

⚠️ 关键前置：验证吞吐必须使用**独立 group.id**，不能与运行中的服务
   共用 group，否则触发持续 rebalance，吞吐会被打到个位数/秒
   （这就是前几轮误诊"代码有性能 bug"的根因）。
"""
import json
import sys
import time
import urllib.request
import urllib.error

sys.path.insert(0, "/app/capstone")
from app import config  # noqa: E402
from app.kafka_client import OrderProducer  # noqa: E402
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


def req(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request(BASE + path, data=data, method=method,
                               headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(r, timeout=30) as resp:
            return resp.status, json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.loads(e.read().decode())
        except Exception:
            return e.code, {}


def stats():
    with urllib.request.urlopen(BASE + "/stats", timeout=20) as r:
        return json.loads(r.read().decode())


print("=" * 74)
print("课 13 · 最终验收（干净环境）")
print("=" * 74)

# ---------- 真实吞吐（独立 group）----------
print("\n[A] 真实吞吐（独立 group.id，无同组竞争）")
N = 5000
TOPIC = "capstone-final"
a = AdminClient({"bootstrap.servers": config.BROKERS})
if TOPIC not in a.list_topics(timeout=10).topics:
    for t, f in a.create_topics([NewTopic(TOPIC, num_partitions=4,
                                          replication_factor=1)]).items():
        f.result()
pp = Producer({"bootstrap.servers": config.BROKERS, "linger.ms": 5})
for i in range(N):
    pp.produce(TOPIC, json.dumps({"order_id": f"f{i:05d}", "user_id": f"u{i%100}",
                                  "amount": 10.0 + i, "currency": "CNY"}).encode())
pp.flush(15)
print(f"    预灌 {N} 条")

gid = f"final-{int(time.time()) % 100000}"   # **独立 group**
conf = dict(config.consumer_conf()); conf["group.id"] = gid
c = Consumer(conf)
c.subscribe([TOPIC])
for _ in range(20):
    c.poll(1.0)
    if c.assignment():
        break
n = 0
t0 = time.time()
while n < N and time.time() - t0 < 60:
    m = c.poll(timeout=1.0)
    if m is None or m.error():
        continue
    n += 1
    try:
        default_process(OrderEvent.from_json(m.value()))
    except Exception:
        pass
    c.commit(message=m, asynchronous=True)
el = time.time() - t0
rate = n / el if el > 0 else 0
print(f"    消费 {n}/{N} 条 / {el:.2f}s = {rate:.0f} 条/秒")
chk("消费吞吐 >1000 条/秒", rate > 1000, f"{rate:.0f}/s")
c.close()

# ---------- 服务 6 能力 ----------
print("\n[B] 服务核心能力")
s0 = stats()
chk("服务就绪（4 分区）", len(s0.get("lag_by_partition", {})) == 4, str(s0)[:120])

batch = [{"order_id": f"FIN-{i:04d}", "user_id": f"u{i%50}",
          "amount": 10.0 + i, "currency": "CNY"} for i in range(200)]
st, b = req("POST", "/orders/batch", batch)
chk("批量投递", st == 200 and b.get("accepted") == 200, f"{st} {str(b)[:120]}")

st, fl = req("POST", "/admin/flush?timeout=15")
chk("全部确认", fl.get("remaining") == 0, str(fl))

time.sleep(6)
s1 = stats()
chk("消费成功", s1["consumed_ok"] > s0["consumed_ok"],
    f"{s0['consumed_ok']}->{s1['consumed_ok']}")
chk("位移已提交", s1["committed"] > s0["committed"], str(s1["committed"]))

st, _ = req("POST", "/orders", {"order_id": "x", "user_id": "u",
                                "amount": -1, "currency": "CNY"})
chk("坏消息被 422 拦截", st == 422, str(st))

# DLQ：直投坏消息
ep = OrderProducer(); ep.start()
ep.produce("bad-final", json.dumps({"order_id": "bad-final", "user_id": "u",
                                    "amount": -999, "currency": "CNY"}).encode())
ep.flush(10); ep.close()
time.sleep(8)
s2 = stats()
chk("坏消息进 DLQ", s2["dlq"] > s1["dlq"], f"{s1['dlq']}->{s2['dlq']}")
chk("识别为 validation_error", s2["validation_error"] > s1["validation_error"],
    f"{s1['validation_error']}->{s2['validation_error']}")

# 指标
m = urllib.request.urlopen(BASE + "/metrics", timeout=20).read().decode()
chk("lag 是 gauge", "# TYPE capstone_consumer_lag gauge" in m, "")
chk("produced 指标", "capstone_orders_produced_total" in m, "")
chk("consumed 指标", "capstone_orders_consumed_total" in m, "")

print("\n" + "=" * 74)
print(f"  通过 {P}  失败 {F}")
print("=" * 74)
print(f"\n  真实消费吞吐 = {rate:.0f} 条/秒")
