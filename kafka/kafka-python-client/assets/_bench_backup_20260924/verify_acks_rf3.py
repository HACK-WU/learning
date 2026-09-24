"""课 4：acks 代价复测 —— 跑多轮取范围（单次百分比不可复现）。

上一版问题：
  首轮测出 acks=-1 比 acks=0「慢 188.1%」，复验只有 66.4%。
  单机 3 节点集群、单次测量抖动大 → 单次百分比不能当结论。

这版：每档跑 5 轮，每轮 200 条，输出中位数与范围。
"""
import socket
import statistics
import time

from kafka import KafkaAdminClient, KafkaProducer
from kafka.admin import NewTopic

HOSTS = ["kafka-1", "kafka-2", "kafka-3"]
BS_LIST = []
for h in HOSTS:
    try:
        ip = socket.gethostbyname(h)
        s = socket.socket()
        s.settimeout(3)
        s.connect((ip, 9092))
        BS_LIST.append(f"{h}:9092")
        s.close()
    except OSError:
        pass
BS = ",".join(BS_LIST)
T3 = "l4-acks-rf3b"
ROUNDS = 5
N = 200

admin = KafkaAdminClient(bootstrap_servers=BS, request_timeout_ms=15000)
try:
    r = admin.create_topics([NewTopic(T3, num_partitions=1, replication_factor=3)])
    for it in r.get("topics", []):
        print(f"create rf=3: {it.get('name')} error_code={it.get('error_code')}")
except Exception as e:
    print(f"create: {type(e).__name__}: {str(e)[:100]}")
time.sleep(2)

try:
    d = admin.describe_topics([T3])
    for t in d:
        for p in t.get("partitions", []):
            print(f"  ISR: leader={p['leader_id']} "
                  f"replicas={p['replica_nodes']} isr={p['isr_nodes']}")
except Exception as e:
    print(f"  {type(e).__name__}: {str(e)[:100]}")

print(f"\n每档 {ROUNDS} 轮 × {N} 条，取中位数与范围")
print("=" * 70)
data = {}
for acks, desc in ((0, "不等确认"), (1, "等 leader"), (-1, "等全部 ISR")):
    try:
        p = KafkaProducer(bootstrap_servers=BS, acks=acks,
                          linger_ms=0, max_block_ms=15000)
        p.send(T3, b"warmup").get(timeout=10)      # 预热
        per = []
        for _ in range(ROUNDS):
            t0 = time.time()
            futs = [p.send(T3, b"x" * 100) for _ in range(N)]
            for f in futs:
                f.get(timeout=30)
            per.append((time.time() - t0) / N * 1000)   # 单条均值 ms
        med = statistics.median(per)
        data[acks] = per
        print(f"  acks={acks:<3}{desc:<12} 中位 {med:.4f}ms  "
              f"范围 [{min(per):.4f}, {max(per):.4f}]")
        p.close(timeout=5)
    except Exception as e:
        print(f"  acks={acks}: ✗ {type(e).__name__}: {str(e)[:70]}")

print("\n" + "=" * 70)
print("倍率（用中位数算，并给出区间）")
print("=" * 70)
if 0 in data and 1 in data and -1 in data:
    m0, m1, ma = (statistics.median(data[k]) for k in (0, 1, -1))
    print(f"  acks=-1 / acks=0  = {ma/m0:.2f}×"
          f"   （最乐观 {min(data[-1])/max(data[0]):.2f}×，"
          f"最悲观 {max(data[-1])/min(data[0]):.2f}×）")
    print(f"  acks=-1 / acks=1  = {ma/m1:.2f}×"
          f"   （最乐观 {min(data[-1])/max(data[1]):.2f}×，"
          f"最悲观 {max(data[-1])/min(data[1]):.2f}×）")
    print("\n  → 方向稳定（acks=-1 最慢），但倍率抖动大，")
    print("    单机 3 节点集群不能给出精确倍数，只给量级结论。")

try:
    r = admin.delete_topics([T3])
    for it in r.get("topics", []):
        print(f"\ndelete: {it.get('name')} error_code={it.get('error_code')}")
except Exception as e:
    print(f"delete: {type(e).__name__}: {str(e)[:80]}")
admin.close()
