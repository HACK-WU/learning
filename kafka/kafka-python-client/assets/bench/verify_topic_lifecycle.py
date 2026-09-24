"""课 3：Topic 生命周期全流程实测（建 → 查 → 改 → 删）。

重点：
  1. 两库操作同一 topic 的真实返回结构（课 2 已知 3.0.11 返回 {'topics':[...]}）
  2. 幂等性：重复建同名 topic 会怎样
  3. 删了立刻建会怎样（异步删除）
  4. error_code 静默失败怎么发现
"""
import time

from kafka import KafkaAdminClient
from kafka.admin import ConfigResource, ConfigResourceType, NewPartitions, NewTopic
from kafka.errors import TopicAlreadyExistsError

BS = "kafka-1:9092,kafka-2:9092,kafka-3:9092"
T = "l3-lifecycle"

admin = KafkaAdminClient(bootstrap_servers=BS, request_timeout_ms=15000)


def show_result(r, label):
    print(f"  [{label}] type={type(r).__name__}")
    if isinstance(r, dict) and "topics" in r:
        for item in r["topics"]:
            ec = item.get("error_code")
            mark = "✓" if ec == 0 else "✗"
            print(f"     {mark} name={item.get('name')} error_code={ec}")
            if ec != 0:
                print(f"        message={item.get('error_message') or item.get('error')}")
    elif isinstance(r, dict):
        for k, v in r.items():
            print(f"     {k}: {v}")
    else:
        print(f"     {r}")


print("=" * 70)
print("1. 创建 topic")
print("=" * 70)
try:
    r = admin.create_topics([NewTopic(T, num_partitions=2, replication_factor=1)])
    show_result(r, "create")
except TopicAlreadyExistsError as e:
    print(f"  TopicAlreadyExistsError: {e}")
except Exception as e:
    print(f"  {type(e).__name__}: {str(e)[:150]}")

time.sleep(1)

print("\n" + "=" * 70)
print("2. 重复创建（幂等性测试）")
print("=" * 70)
try:
    r = admin.create_topics([NewTopic(T, num_partitions=2, replication_factor=1)])
    show_result(r, "create again")
    print("  ↑ 注意：没抛异常，但 error_code 可能非 0 → 静默失败")
except TopicAlreadyExistsError as e:
    print(f"  ✓ 抛 TopicAlreadyExistsError（显式失败）: {str(e)[:100]}")
except Exception as e:
    print(f"  {type(e).__name__}: {str(e)[:150]}")

print("\n" + "=" * 70)
print("3. 查询元数据（list_topics / describe_topics）")
print("=" * 70)
topics = admin.list_topics()
print(f"  集群 topic 数 = {len(topics)}")
print(f"  含 {T}: {T in topics}")

if T in topics:
    from kafka.admin import ConfigResource
    try:
        d = admin.describe_topics([T])
        print(f"  describe_topics 返回 type={type(d).__name__}")
        if isinstance(d, list):
            for t in d:
                print(f"    topic={t.get('topic')}")
                for p in t.get("partitions", []):
                    print(f"      p{p['partition']}: leader={p['leader']} "
                          f"replicas={p['replicas']} isr={p['isr']}")
        elif isinstance(d, dict):
            print(f"    {d}")
    except Exception as e:
        print(f"  describe_topics 失败: {type(e).__name__}: {str(e)[:120]}")

print("\n" + "=" * 70)
print("4. 扩容分区（create_partitions）")
print("=" * 70)
try:
    r = admin.create_partitions({T: NewPartitions(total_count=4)})
    print(f"  返回 type={type(r).__name__}: {r}")
    time.sleep(1)
    d = admin.describe_topics([T])
    if isinstance(d, list):
        print(f"  扩容后分区数 = {len(d[0]['partitions'])}")
except Exception as e:
    print(f"  {type(e).__name__}: {str(e)[:150]}")

print("\n" + "=" * 70)
print("5. 查询/修改配置（describe_configs / alter_configs）")
print("=" * 70)
try:
    cr = ConfigResource(ConfigResourceType.TOPIC, T)
    r = admin.describe_configs([cr])
    print(f"  describe_configs type={type(r).__name__}")
    if isinstance(r, list) and r:
        res = r[0]
        print(f"    resources={len(res.resources) if hasattr(res,'resources') else '?'}")
        cfg = getattr(res, "resources", None)
        if cfg:
            for c in cfg[:5]:
                print(f"      {getattr(c,'name',None)} = {getattr(c,'value',None)}")
except Exception as e:
    print(f"  失败: {type(e).__name__}: {str(e)[:150]}")

print("\n" + "=" * 70)
print("6. 删除 topic")
print("=" * 70)
try:
    r = admin.delete_topics([T])
    show_result(r, "delete")
except Exception as e:
    print(f"  {type(e).__name__}: {str(e)[:150]}")

print("\n" + "=" * 70)
print("7. 删除后立刻查（验证异步删除）")
print("=" * 70)
for i in range(5):
    topics = admin.list_topics()
    print(f"  第 {i+1} 次查询: {T} 存在 = {T in topics}")
    if T not in topics:
        break
    time.sleep(1)

admin.close()
