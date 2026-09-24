"""课 1：打印 describe_cluster() 的原始返回结构（不猜属性名）。"""
import json

from kafka import KafkaAdminClient

BS = "kafka-1:9092,kafka-2:9092,kafka-3:9092"
admin = KafkaAdminClient(bootstrap_servers=BS, request_timeout_ms=10000)

print("=== describe_cluster() 原始结果 ===")
meta = admin.describe_cluster()
print(json.dumps(meta, default=str, indent=2, ensure_ascii=False))

print()
print("=== cluster.brokers 原始结果 ===")
try:
    bs = admin._client.cluster.brokers()
    print(f"  类型: {type(bs).__name__}, 长度: {len(bs)}")
    for b in bs:
        print(f"    {b}")
        if hasattr(b, "__dict__"):
            for k, v in vars(b).items():
                print(f"        {k} = {v}")
        elif hasattr(b, "_asdict"):
            for k, v in b._asdict().items():
                print(f"        {k} = {v}")
except Exception as e:
    print(f"  失败: {type(e).__name__}: {e}")

admin.close()
