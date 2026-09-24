"""课 1 环境基线核验：docker / 集群 / 网络 / uv 状态（只读）。"""
import socket
import subprocess

NET = "stage6-observability_kafka-net"
HOSTS = ["kafka-1", "kafka-2", "kafka-3", "l15-kafka-1", "l15-kafka-2", "l15-kafka-3"]

print("=== 1. 容器状态 ===")
out = subprocess.run(
    ["docker", "ps", "-a", "--format", "{{.Names}}\t{{.Image}}\t{{.Status}}"],
    capture_output=True, text=True,
)
for line in out.stdout.strip().splitlines():
    print("  ", line)

print()
print("=== 2. 网络列表 ===")
out = subprocess.run(["docker", "network", "ls"], capture_output=True, text=True)
for line in out.stdout.strip().splitlines():
    print("  ", line)

print()
print("=== 3. 关键主机名解析 ===")
ips = {}
for h in HOSTS:
    try:
        ip = socket.gethostbyname(h)
        ips[h] = ip
        print(f"  {h:16s} → {ip}")
    except socket.gaierror:
        print(f"  {h:16s} DNS 解析失败")

print()
print("=== 4. IP 去重（判断 kafka-N 与 l15-kafka-N 是否同一批） ===")
seen = {}
for h, ip in ips.items():
    seen.setdefault(ip, []).append(h)
for ip, hs in seen.items():
    flag = " ← 同一容器多个别名" if len(hs) > 1 else ""
    print(f"  {ip}: {', '.join(hs)}{flag}")
