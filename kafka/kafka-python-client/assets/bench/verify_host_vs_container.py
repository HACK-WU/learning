"""课 1 反证：宿主机视角直连映射端口会怎样。

预期：宿主机能解析/连到 172.20.x 吗？不能（docker 网桥在 WSL 内）。
在 WSL 宿主机里试连 172.20.0.3:9092 与 localhost:19192 等。
"""
import socket

CANDIDATES = [
    ("127.0.0.1", 9092),
    ("127.0.0.1", 19192),
    ("127.0.0.1", 19193),
    ("172.20.0.3", 9092),
    ("172.20.0.4", 9092),
    ("172.20.0.5", 9092),
    ("kafka-1", 9092),
    ("l15-kafka-1", 9092),
]

print("=== 从 WSL 宿主机视角尝试连接 ===")
for host, port in CANDIDATES:
    try:
        ip = socket.gethostbyname(host)
    except socket.gaierror:
        print(f"  {host}:{port:<6} ✗ DNS 解析失败")
        continue
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(3)
    try:
        s.connect((ip, port))
        print(f"  {host}:{port:<6} ✓ TCP 可连（{ip}）")
    except OSError as e:
        print(f"  {host}:{port:<6} ✗ {type(e).__name__}")
    finally:
        s.close()

print()
print("=== 结论提示 ===")
print("  若上面全 ✗ → 说明宿主机进不去 docker 网桥，")
print("  必须把客户端跑在容器里并加入同一网络：")
print("  docker run --network stage6-observability_kafka-net ...")
