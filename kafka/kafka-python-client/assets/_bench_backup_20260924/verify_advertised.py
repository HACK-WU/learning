"""课 1：拿到 advertised.listeners 的真相 —— 证明宿主机直连为什么不行。

上一版 describe_cluster 属性名猜错（返回 ?）。这版不猜，直接枚举对象属性。
"""
from kafka import KafkaAdminClient

BS = "kafka-1:9092,kafka-2:9092,kafka-3:9092"

admin = KafkaAdminClient(bootstrap_servers=BS, request_timeout_ms=10000)

print("=== describe_cluster() 返回对象的真实属性 ===")
meta = admin.describe_cluster()
print("  类型:", type(meta).__name__)
for attr in dir(meta):
    if attr.startswith("_"):
        continue
    try:
        val = getattr(meta, attr)
        if callable(val):
            continue
        print(f"    {attr} = {val}")
    except Exception as e:
        print(f"    {attr} → 读取失败 {type(e).__name__}")

print()
print("=== 另一种拿法：_client.cluster 里的 broker 元数据 ===")
try:
    cl = admin._client.cluster
    for node_id, broker in cl.brokers().items() if callable(cl.brokers) else []:
        print(f"  broker {node_id}: host={getattr(broker,'host',None)} "
              f"port={getattr(broker,'port',None)}")
except Exception as e:
    print(f"  失败: {type(e).__name__}: {e}")

print()
print("=== 用 kafka-python 的 _metadata 直接看 ===")
try:
    for b in admin._client.cluster._brokers.values():
        print(f"  nodeId={b.nodeId}  host={b.host}  port={b.port}  rack={getattr(b,'rack',None)}")
        if b.host and not b.host.replace('.', '').isdigit():
            print(f"      ↑ 是主机名（{b.host}），不是 IP")
            print(f"        宿主机若无法解析 {b.host}，即使 TCP 连上 9092，")
            print(f"        后续元数据返回该地址时也会连不上 → 直连必失败")
except Exception as e:
    print(f"  失败: {type(e).__name__}: {e}")

admin.close()
