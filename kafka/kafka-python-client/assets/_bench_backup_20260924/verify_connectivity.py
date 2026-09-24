"""课 1 实操：连通性自检 —— 证明"连上了"不等于"能用"。

核心教学点（主教程课 15 实测过的坑）：
  broker 的 advertised.listeners 是容器名 kafka-1:9092。
  宿主机直连映射端口 19192 时，TCP 能连上、握手也能过，
  但拿到的是 kafka-1:9092 这个宿主机不可达的地址 → 后续收发必失败。
  只有跑在容器网络里才能正常用。

本脚本分层核验：DNS → TCP → Kafka 握手 → 真实收发 → advertised.listeners 真相
"""

import socket
import subprocess

from kafka import KafkaAdminClient, KafkaConsumer, KafkaProducer
from kafka.errors import KafkaError

HOSTS = ["kafka-1", "kafka-2", "kafka-3", "l15-kafka-1", "l15-kafka-2", "l15-kafka-3"]

print("=== 第 1 层：DNS 解析 ===")
resolved = {}
for h in HOSTS:
    try:
        ip = socket.gethostbyname(h)
        resolved[h] = ip
        print(f"  {h:14s} → {ip}")
    except socket.gaierror:
        print(f"  {h:14s} ✗ 解析失败")

print("\n=== 第 2 层：IP 归并（谁和谁是同一台） ===")
by_ip = {}
for h, ip in resolved.items():
    by_ip.setdefault(ip, []).append(h)
for ip, hs in sorted(by_ip.items()):
    tag = "  ← 同一容器的多个别名" if len(hs) > 1 else ""
    print(f"  {ip:15s} {', '.join(hs)}{tag}")

print("\n=== 第 3 层：TCP 连通（9092） ===")
ok_hosts = []
for h in resolved:
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(3)
    try:
        s.connect((resolved[h], 9092))
        print(f"  {h}:9092  ✓ TCP 可连")
        ok_hosts.append(h)
    except OSError as e:
        print(f"  {h}:9092  ✗ {type(e).__name__}")
    finally:
        s.close()

if not ok_hosts:
    print("\n无可用 broker，后续步骤跳过")
    raise SystemExit(1)

BS = ",".join(f"{h}:9092" for h in ok_hosts[:3])
print(f"\n=== 第 4 层：Kafka 协议握手（bootstrap={BS}） ===")
admin = None
try:
    admin = KafkaAdminClient(bootstrap_servers=BS,
                             request_timeout_ms=10000, client_id="l1-probe")
    topics = sorted(admin.list_topics())
    print(f"  ✓ 握手成功，topic 数 = {len(topics)}")
    print(f"    {topics}")
except Exception as e:
    print(f"  ✗ 握手失败：{type(e).__name__}: {str(e)[:150]}")
    raise SystemExit(1)

print("\n=== 第 5 层：advertised.listeners 真相（为什么宿主机直连不行） ===")
try:
    meta = admin.describe_cluster()          # 实测返回 dict，不是对象
    print(f"  cluster_id   = {meta.get('cluster_id')}")
    print(f"  controller_id= {meta.get('controller_id')}")
    for b in meta.get("brokers", []):        # 键是 broker_id，不是 nodeId
        host = b.get("host")
        port = b.get("port")
        print(f"  broker {b.get('broker_id')}: {host}:{port}")
        if host and not host.replace(".", "").isdigit():
            print(f"      ↑ 广播的是主机名（{host}）而非 IP")
            print(f"        客户端所在环境必须能解析 {host}，否则后续收发必失败")
except Exception as e:
    print(f"  元数据读取失败：{type(e).__name__}: {str(e)[:150]}")

print("\n=== 第 6 层：真实收发（证明真的能用，不只是连上） ===")
TOPIC = "l1-connectivity-check"
try:
    if TOPIC not in topics:
        from kafka.admin import NewTopic
        admin.create_topics([NewTopic(TOPIC, num_partitions=1, replication_factor=1)])
        print(f"  建 topic {TOPIC}")
    p = KafkaProducer(bootstrap_servers=BS)
    fut = p.send(TOPIC, b"hello-lesson1")
    md_ = fut.get(timeout=10)
    print(f"  ✓ 发送成功 partition={md_.partition} offset={md_.offset}")
    p.flush()
    p.close()

    c = KafkaConsumer(TOPIC, bootstrap_servers=BS, group_id="l1-check",
                      auto_offset_reset="earliest",
                      consumer_timeout_ms=8000)
    got = 0
    for msg in c:
        print(f"  ✓ 收到：{msg.value.decode()} (p{msg.partition}@{msg.offset})")
        got += 1
    c.close()
    print(f"  共收到 {got} 条 → 收发链路完整 ✓")
except Exception as e:
    print(f"  ✗ 收发失败：{type(e).__name__}: {str(e)[:200]}")
finally:
    try:
        admin.delete_topics([TOPIC])
        print(f"  已清理 {TOPIC}")
    except Exception:
        pass
    if admin:
        admin.close()

print("\n=== 自检完成 ===")
