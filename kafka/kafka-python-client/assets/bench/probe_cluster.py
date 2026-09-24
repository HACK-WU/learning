"""开工前连通性核验：确认当前到底能连哪个 Kafka 集群。

背景：课 8 结束时的 3 节点 SASL 集群（kafka-1/2/3）疑似已不存在，
       docker ps 只看到 l15-kafka-1/2/3（主教程课 15 的无 SASL 集群）。
       但上轮吞吐实测跑通了，需要弄清当时到底连的是谁、现在还能不能连。

核验点：
  1. 解析 stage6-observability_kafka-net 上还能解析到哪些 kafka 主机名
  2. 分别试连 9092（容器内网）与各集群，确认能否建连
  3. 确认 l15 集群是否在同一网络、端口是多少
"""

import socket

from kafka import KafkaProducer
from kafka.admin import KafkaAdminClient
from kafka.errors import KafkaError

CANDIDATES = [
    ("kafka-1", 9092),
    ("kafka-2", 9092),
    ("kafka-3", 9092),
    ("l15-kafka-1", 9092),
    ("l15-kafka-2", 9092),
    ("l15-kafka-3", 9092),
    ("host.docker.internal", 19192),
    ("host.docker.internal", 19193),
    ("host.docker.internal", 19194),
]

print("=== 1. DNS 解析 + TCP 连通性 ===")
reachable = []
for host, port in CANDIDATES:
    try:
        ip = socket.gethostbyname(host)
    except socket.gaierror:
        print(f"  {host}:{port}  DNS 解析失败")
        continue
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(3)
    try:
        s.connect((ip, port))
        print(f"  {host}:{port}  ✅ TCP 可连（{ip}）")
        reachable.append((host, port))
    except OSError as e:
        print(f"  {host}:{port}  ❌ 连不上（{type(e).__name__}）")
    finally:
        s.close()
print()

print("=== 2. 对可连地址尝试 Kafka 协议握手（无 SASL） ===")
for host, port in reachable:
    bootstrap = f"{host}:{port}"
    try:
        admin = KafkaAdminClient(
            bootstrap_servers=bootstrap,
            request_timeout_ms=8000,
            client_id="probe",
        )
        topics = admin.list_topics()
        print(f"  {bootstrap}  ✅ Kafka 握手成功，topic 数={len(topics)}")
        print(f"     topics: {sorted(topics)[:10]}")
        admin.close()
    except KafkaError as e:
        print(f"  {bootstrap}  ❌ Kafka 握手失败：{type(e).__name__}: {e}")
    except Exception as e:
        print(f"  {bootstrap}  ❌ 异常：{type(e).__name__}: {e}")
print()

print("=== 3. 尝试带 SASL 连接（课 8 的凭据） ===")
from kafka.admin import KafkaAdminClient as Admin

sasl_conf = {
    "security_protocol": "SASL_PLAINTEXT",
    "sasl_mechanism": "SCRAM-SHA-512",
    "sasl_plain_username": "admin",
    "sasl_plain_password": "admin-secret",
}
for host, port in [("kafka-1", 9092), ("l15-kafka-1", 9092)]:
    bootstrap = f"{host}:{port}"
    try:
        admin = Admin(
            bootstrap_servers=bootstrap,
            request_timeout_ms=8000,
            client_id="probe-sasl",
            **sasl_conf,
        )
        topics = admin.list_topics()
        print(f"  {bootstrap}  ✅ SASL 握手成功，topic 数={len(topics)}")
        admin.close()
    except Exception as e:
        print(f"  {bootstrap}  ❌ SASL 失败：{type(e).__name__}: {str(e)[:120]}")
