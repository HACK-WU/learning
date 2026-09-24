"""课 3：AdminClient 两库（kafka-python vs confluent）API 对照。

注：aiokafka 没有独立的 AdminClient（用 AIOKafkaAdminClient，
本课聚焦两库对照 —— 先确认 aiokafka 到底有没有）。

方法：hasattr 实测，不猜。
"""
from confluent_kafka.admin import AdminClient as CfAdmin
from kafka import KafkaAdminClient

print("=== 1. aiokafka 有没有 AdminClient ===")
try:
    import aiokafka

    names = [n for n in dir(aiokafka) if "Admin" in n]
    print(f"  aiokafka 里含 Admin 的名字: {names}")
    if names:
        from aiokafka.admin import AIOKafkaAdminClient
        print(f"  AIOKafkaAdminClient 存在")
        print(f"  方法: {[m for m in dir(AIOKafkaAdminClient) if not m.startswith('_') and 'topic' in m.lower()]}")
except Exception as e:
    print(f"  失败: {type(e).__name__}: {e}")

# Admin 侧常见操作
ADMIN_APIS = [
    # topic 生命周期
    "create_topics", "delete_topics", "list_topics", "describe_topics",
    "create_partitions", "alter_configs", "describe_configs",
    # 消费组
    "list_consumer_groups", "list_consumer_group_offsets",
    "describe_consumer_groups", "delete_consumer_groups",
    "alter_consumer_group_offsets",
    # 集群/ACL
    "describe_cluster", "create_acls", "describe_acls", "delete_acls",
    # 其他
    "describe_client_quotas", "elect_leaders", "list_offsets",
]


def probe(cls, label):
    print(f"\n=== {label} ===")
    present, absent = [], []
    for a in ADMIN_APIS:
        if hasattr(cls, a):
            present.append(a)
        else:
            absent.append(a)
    print(f"  存在 ({len(present)}):")
    for p in present:
        print(f"     ✓ {p}")
    print(f"  缺失 ({len(absent)}):")
    for a in absent:
        print(f"     ✗ {a}")
    return set(present)


kp = probe(KafkaAdminClient, "kafka-python · KafkaAdminClient")
cf = probe(CfAdmin, "confluent-kafka · AdminClient")

print("\n" + "=" * 70)
print("交叉对比（只在部分库存在 → 换库会崩）")
print("=" * 70)
print(f"{'API':<38}{'kafka-python':<16}{'confluent'}")
print("-" * 70)
for a in sorted(ADMIN_APIS):
    m1 = "✓" if a in kp else "✗"
    m2 = "✓" if a in cf else "✗"
    print(f"{a:<38}{m1:<16}{m2}")
    cnt = sum(a in s for s in (kp, cf))
    if 0 < cnt < 2:
        print(f"{'':<38}↑ 仅 1/2 库有 → 换库风险")

print("\n=== 命名风格差异统计 ===")
only_kp = sorted(kp - cf)
only_cf = sorted(cf - kp)
print(f"  仅 kafka-python 有: {only_kp}")
print(f"  仅 confluent 有:   {only_cf}")
