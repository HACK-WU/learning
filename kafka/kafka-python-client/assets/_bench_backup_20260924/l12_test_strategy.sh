#!/bin/bash
# 课 12 知识点3：测试策略实测
#   方案1: MockProducer（confluent 自带，零依赖）
#   方案2: 真 Kafka（testcontainers 需 docker-in-docker，本机评估）
#   方案3: 直连本机 3 节点集群（本环境最省事）
# 观测：各自能测到什么、测不到什么
set -u
cat > /tmp/l12_test.py <<'PYEOF'
import time, json, sys
def banner(t): print(f"\n{'─'*74}\n{t}\n{'─'*74}")

# ═══ 方案1: MockProducer / MockConsumer ═══
banner("方案1 · confluent 自带 Mock（零外部依赖）")
from confluent_kafka import Producer, Consumer, KafkaError, KafkaException
import confluent_kafka
has_mock = hasattr(confluent_kafka, "MockProducer") or True
try:
    from confluent_kafka import MockProducer, MockConsumer
    print("  ✓ MockProducer / MockConsumer 可 import")
except ImportError as e:
    print(f"  ✗ 无 Mock: {e}"); MockProducer=None; MockConsumer=None

if MockProducer:
    mp=MockProducer()
    errs=[]
    def cb(err,msg):
        if err: errs.append(err)
    for i in range(10): mp.produce("t",json.dumps({"i":i}).encode(),callback=cb)
    mp.flush(5)
    print(f"  生产 10 条：错误 {len(errs)} 个，队列剩余 {len(mp)}")
    print(f"  -> 能测：回调逻辑、序列化、错误处理")
    print(f"  -> 不能测：真实网络、分区分配、再均衡、位移提交")

# ═══ 方案2: testcontainers 可用性 ═══
banner("方案2 · testcontainers（需 docker-in-docker）")
try:
    import testcontainers
    print(f"  ✓ testcontainers 已装 {testcontainers.__version__}")
except ImportError:
    print("  ✗ 未安装 testcontainers")
try:
    import docker
    print(f"  ✓ docker SDK 已装 {docker.__version__}")
except ImportError:
    print("  ✗ 未安装 docker SDK")

# ═══ 方案3: 直连本机集群（本环境最优解）═══
banner("方案3 · 直连本机 3 节点集群（本环境实测）")
BROKERS="kafka-1:9092,kafka-2:9092,kafka-3:9092"
from confluent_kafka.admin import AdminClient, NewTopic
a=AdminClient({"bootstrap.servers":BROKERS})
t0=time.time()
md=a.list_topics(timeout=10)
print(f"  ✓ 连集群成功，{len(md.topics)} 个 topic，耗时 {time.time()-t0:.3f}s")
# 建临时 topic -> 测 -> 删（测试隔离的核心手法）
TEST_TOPIC=f"l12-test-{int(time.time())%100000}"
fs=a.create_topics([NewTopic(TEST_TOPIC,num_partitions=2,replication_factor=1)])
for tp,f in fs.items():
    try: f.result(); print(f"  ✓ 建测试 topic {tp}")
    except Exception as e: print(f"  ✗ {e}")
# 真实收发
p=Producer({"bootstrap.servers":BROKERS})
for i in range(5): p.produce(TEST_TOPIC,json.dumps({"i":i}).encode())
p.flush(10)
c=Consumer({"bootstrap.servers":BROKERS,"group.id":f"g-{int(time.time())%100000}",
            "auto.offset.reset":"earliest","enable.auto.commit":False})
from confluent_kafka import TopicPartition
c.assign([TopicPartition(TEST_TOPIC,0),TopicPartition(TEST_TOPIC,1)])
got=len(c.consume(num_messages=5,timeout=10))
print(f"  ✓ 真实收发 {got}/5 条")
c.close()
# 清理
ds=a.delete_topics([TEST_TOPIC])
for tp,f in ds.items():
    try: f.result(); print(f"  ✓ 清理测试 topic {tp}")
    except Exception as e: print(f"  ✗ 清理失败: {e}")

banner("三种方案取舍")
print("""  Mock          : 毫秒级、零依赖、CI 友好   -> 业务逻辑单测
  真集群(本机)  : 秒级、能测真实语义        -> 集成测试（本环境推荐）
  testcontainers: 需 docker-in-docker      -> 容器内跑测试时才需要""")
PYEOF
docker cp /tmp/l12_test.py l11:/tt.py >/dev/null
docker exec l11 /app/.venv/bin/python /tt.py 2>&1 \
  | grep -v -e Authlib -e 'from ._compat' | head -40
