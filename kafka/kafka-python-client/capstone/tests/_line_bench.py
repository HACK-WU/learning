"""逐行排除 _handle 里的开销。
_handle 完整逻辑 = 16.5/s，裸循环 = 74233/s。
差异行：OrderEvent.from_json / default_process / metrics.CONSUMED.inc / commit
逐个加回去，看速率在哪一步崩掉。
"""
import json
import sys
import time

sys.path.insert(0, "/app/capstone")
from app import config, metrics  # noqa: E402
from app.schema import OrderEvent  # noqa: E402
from app.worker import default_process  # noqa: E402
from confluent_kafka import Consumer, Producer  # noqa: E402
from confluent_kafka.admin import AdminClient, NewTopic  # noqa: E402

N = 800
a = AdminClient({"bootstrap.servers": config.BROKERS})


def mk_topic(name):
    if name not in a.list_topics(timeout=10).topics:
        for t, f in a.create_topics([NewTopic(name, num_partitions=4,
                                              replication_factor=1)]).items():
            f.result()
    p = Producer({"bootstrap.servers": config.BROKERS, "linger.ms": 5})
    for i in range(N):
        p.produce(name, json.dumps({"order_id": f"x{i:05d}", "user_id": "u",
                                    "amount": 10.0 + i, "currency": "CNY"}).encode())
    p.flush(15)
    return name


def bench(label, fn_per_msg, do_commit):
    top = mk_topic(f"capstone-{label}")
    c = Consumer(config.consumer_conf())
    c.subscribe([top])
    for _ in range(20):
        c.poll(1.0)
        if len(c.assignment()) == 4:
            break
    parts = len(c.assignment())
    n = 0
    t0 = time.time()
    while n < N and time.time() - t0 < 40:
        m = c.poll(timeout=1.0)
        if m is None or m.error():
            continue
        n += 1
        if fn_per_msg:
            fn_per_msg(m)
        if do_commit:
            c.commit(message=m, asynchronous=True)
    el = time.time() - t0
    rate = n / el if el > 0 else 0
    print(f"  {label:<30}{n:>4}条 {el:>6.2f}s {rate:>10.1f}/s parts={parts}")
    c.close()
    return rate


print("=" * 74)
print("课13 · _handle 逐行排除")
print("=" * 74 + "\n")

r0 = bench("A", None, False)              # 裸循环


def f_parse(m):
    OrderEvent.from_json(m.value())


r1 = bench("B", f_parse, False)           # + from_json


def f_parse_proc(m):
    default_process(OrderEvent.from_json(m.value()))


r2 = bench("C", f_parse_proc, False)      # + default_process


def f_metric(m):
    metrics.CONSUMED.inc(1, result="ok")


r3 = bench("D", f_metric, False)          # 仅 metrics.inc
r4 = bench("E", None, True)               # 仅 commit


def f_all(m):
    default_process(OrderEvent.from_json(m.value()))
    metrics.CONSUMED.inc(1, result="ok")


r5 = bench("F", f_all, False)             # 解析 + metrics
r6 = bench("G", f_all, True)              # 全量

print(f"\n  {'配置':<34}{'速率':>12}{'相对裸循环':>14}")
print(f"  {'-'*60}")
for nm, r in (("A 裸循环", r0), ("B +from_json", r1), ("C +process", r2),
              ("D 仅metrics.inc", r3), ("E 仅commit", r4),
              ("F 解析+metrics", r5), ("G 全量", r6)):
    rel = f"{r/r0:.3f}x" if r0 else "n/a"
    print(f"  {nm:<32}{r:>10.1f}/s{rel:>14}")

print(f"\n  判据：速率在哪一行崩掉，那行就是真凶")
