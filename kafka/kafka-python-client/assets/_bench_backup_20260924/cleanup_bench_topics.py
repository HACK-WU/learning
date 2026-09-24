"""清理吞吐实测残留的 bench-* topic，并输出集群健康基线。

清理范围严格限定：只删 bench-confluent-r* / bench-kafkapython-r*（本子教程自己造的）。
保留：__consumer_offsets、acl-deny-demo（课 8 资产，不属于本轮）。
"""

from kafka import KafkaAdminClient
from kafka.admin import NewTopic
from kafka.errors import UnknownTopicOrPartitionError

BOOTSTRAP = "kafka-1:9092,kafka-2:9092,kafka-3:9092"

admin = KafkaAdminClient(bootstrap_servers=BOOTSTRAP, request_timeout_ms=15000)

existing = sorted(admin.list_topics())
print("清理前 topics:", existing)
print()

to_delete = [t for t in existing if t.startswith("bench-")]
print(f"待删除 bench-* topic（{len(to_delete)} 个）:", to_delete)

if to_delete:
    try:
        admin.delete_topics(to_delete)
        print("✅ delete_topics 已提交")
    except UnknownTopicOrPartitionError as e:
        print("⚠️ 部分 topic 已不存在:", e)
    except Exception as e:
        print(f"❌ 删除失败：{type(e).__name__}: {e}")
else:
    print("无需删除")
print()

import time
time.sleep(3)

after = sorted(admin.list_topics())
print("清理后 topics:", after)
remaining_bench = [t for t in after if t.startswith("bench-")]
print(f"残留 bench-* : {remaining_bench if remaining_bench else '无 ✅'}")
print()

print("=== 集群健康基线 ===")
cluster = admin.describe_cluster()
print("Broker 数:", len(cluster["brokers"]))
for b in cluster["brokers"]:
    print(f"  node_id={b['node_id']}  host={b['host']}:{b['port']}")
admin.close()

from kafka import KafkaConsumer
from kafka.structs import TopicPartition
consumer = KafkaConsumer(bootstrap_servers=BOOTSTRAP, request_timeout_ms=15000)
parts = {}
for t in after:
    if t.startswith("__"):
        continue
    parts[t] = sorted(consumer.partitions_for_topic(t) or [])
consumer.close()
print("各 topic 分区:", parts)
