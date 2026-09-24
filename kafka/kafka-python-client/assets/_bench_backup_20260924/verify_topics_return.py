"""课 2：查清 kafka-python 的 create_topics / delete_topics 到底返回什么类型。

复验时发现 AttributeError: 'list' object has no attribute 'result'
—— 说明返回值不是 dict[str, Future]。这版探明真实类型。
"""
from kafka import KafkaAdminClient
from kafka.admin import NewTopic

admin = KafkaAdminClient(bootstrap_servers="kafka-1:9092,kafka-2:9092,kafka-3:9092",
                         request_timeout_ms=10000)

T = "l2-ret-probe"

print("=== create_topics 返回类型 ===")
try:
    r = admin.create_topics([NewTopic(T, num_partitions=1, replication_factor=1)])
    print(f"  type = {type(r).__name__}")
    print(f"  repr = {r!r}")
    if isinstance(r, dict):
        print("  → dict，按 items() 遍历 Future")
        for t, f in r.items():
            print(f"    {t} -> {type(f).__name__}")
            f.result()
    elif isinstance(r, list):
        print("  → list，无需 .result()")
except Exception as e:
    print(f"  失败: {type(e).__name__}: {str(e)[:120]}")

print("\n=== delete_topics 返回类型 ===")
try:
    r2 = admin.delete_topics([T])
    print(f"  type = {type(r2).__name__}")
    print(f"  repr = {r2!r}")
    if isinstance(r2, dict):
        for t, f in r2.items():
            f.result()
        print("  → dict 已等待完成")
    else:
        print("  → list，删除请求已发出（异步生效）")
except Exception as e:
    print(f"  失败: {type(e).__name__}: {str(e)[:120]}")

admin.close()
