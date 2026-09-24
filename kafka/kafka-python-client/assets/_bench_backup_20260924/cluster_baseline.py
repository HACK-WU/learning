"""输出集群健康基线（订正 describe_cluster 的返回结构）。

上一版用 b['node_id'] 报 KeyError —— 实际是 BrokerMetadata 命名元组，用属性访问。
"""

from kafka import KafkaAdminClient, KafkaConsumer

BOOTSTRAP = "kafka-1:9092,kafka-2:9092,kafka-3:9092"

admin = KafkaAdminClient(bootstrap_servers=BOOTSTRAP, request_timeout_ms=15000)
cluster = admin.describe_cluster()

print("=== Broker 列表 ===")
brokers = cluster["brokers"]
for b in brokers:
    print(f"  {b}")
print("Broker 数:", len(brokers))
print("Controller:", cluster.get("controller"))
print("Cluster ID:", cluster.get("cluster_id"))
admin.close()
print()

print("=== Topic / 分区基线 ===")
consumer = KafkaConsumer(bootstrap_servers=BOOTSTRAP, request_timeout_ms=15000)
topics = sorted(consumer.partitions_for_topic("__consumer_offsets") or [])
print("__consumer_offsets 分区数:", len(topics))
all_topics = sorted(t for t in consumer.topics())
print("全部 topic:", all_topics)
consumer.close()
