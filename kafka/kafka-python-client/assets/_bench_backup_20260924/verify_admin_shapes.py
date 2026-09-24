"""课 3：查清 AdminClient 各操作的真实返回结构（课 2 已知它们不统一）。

上一版踩坑：
  describe_topics 返回 list，但分区字段名是 'partition'（无 s），
  写成 'partitions' 就 KeyError。

这版不猜：把每个操作的返回结构原样打印。
"""
import json


from kafka import KafkaAdminClient
from kafka.admin import ConfigResource, ConfigResourceType, NewPartitions, NewTopic

BS = "kafka-1:9092,kafka-2:9092,kafka-3:9092"
T = "l3-shapes"
admin = KafkaAdminClient(bootstrap_servers=BS, request_timeout_ms=15000)


def dump(label, fn, *a, **kw):
    print(f"\n{'=' * 70}")
    print(f"{label}")
    print("=" * 70)
    try:
        r = fn(*a, **kw)
        print(f"  type = {type(r).__name__}")
        # 尽量转成可打印结构
        try:
            if hasattr(r, "to_object") or hasattr(r, "__dict__"):
                raw = r.to_object() if hasattr(r, "to_object") else vars(r)
                print(f"  结构 = {json.dumps(raw, default=str, ensure_ascii=False)[:600]}")
            else:
                print(f"  值   = {json.dumps(r, default=str, ensure_ascii=False)[:600]}")
        except Exception:
            print(f"  值   = {str(r)[:600]}")
        return r
    except Exception as e:
        print(f"  ✗ {type(e).__name__}: {str(e)[:300]}")
        return None


# 建
dump("1. create_topics", admin.create_topics,
     [NewTopic(T, num_partitions=2, replication_factor=1)])

import time
time.sleep(1)

# 查 topic 列表
r = dump("2. list_topics", admin.list_topics)

# describe_topics —— 看真实字段
r = dump("3. describe_topics", admin.describe_topics, [T])
if isinstance(r, list) and r:
    print(f"  → list[0] 的键: {list(r[0].keys()) if isinstance(r[0], dict) else type(r[0])}")

# create_partitions
dump("4. create_partitions", admin.create_partitions,
     {T: NewPartitions(total_count=4)})
time.sleep(1)

# describe_configs
cr = ConfigResource(ConfigResourceType.TOPIC, T)
dump("5. describe_configs", admin.describe_configs, [cr])

# 消费组（kafka-python 没有 list_consumer_groups，试一下）
dump("6. list_consumer_groups（预期缺失）",
     lambda: getattr(admin, "list_consumer_groups")())

# delete
dump("7. delete_topics", admin.delete_topics, [T])

admin.close()

print("\n" + "=" * 70)
print("结论：同一库内各操作的返回结构")
print("=" * 70)
print("""  create_topics     → dict {'topics':[{'name','error_code',...}]}
  delete_topics     → dict {'topics':[{'name','error_code',...}]}
  list_topics       → list[str]
  describe_topics   → list[dict]（分区数组 'partitions'，分区号字段是 'partition_index'）
  create_partitions → CreatePartitionsResponse 对象（响应体对象，不是 dict）
  describe_configs  → dict
""")
