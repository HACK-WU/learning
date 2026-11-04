"""M3：gRPC 到底是"按连接"分还是"按请求"分？

三个后端实例，一个客户端。只做两件事：
  ① 默认策略（pick_first）发 12 次，看落在哪
  ② round_robin 策略发 12 次，看落在哪

结论取决于 per-call 还是 per-connection —— 这是课 8 知识点 2 的地基。
"""
import json

import grpc

from _grpc_backend import (
    ROUND_ROBIN_OPTS,
    Registry,
    make_server,
    make_stub,
    target_of,
)


def run(ports, opts, calls, label):
    reg = Registry()
    servers = []
    for i, p in enumerate(ports, 1):
        s, bound = make_server(f"n{i}", p, reg)
        servers.append((s, bound))
    real_ports = [b for _, b in servers]

    # 连接多个地址：故意用 ipv4:a,b,c 的写法，让 resolver 拿到 3 个地址
    ch = grpc.insecure_channel(target_of(real_ports), options=opts)
    stub = make_stub(ch)
    grpc.channel_ready_future(ch).result(timeout=10)

    for _ in range(calls):
        stub(b"", timeout=5)

    hits = reg.snapshot()
    print(f"\n【{label}】{calls} 次调用，3 个后端")
    for sid in ["n1", "n2", "n3"]:
        c = hits.get(sid, 0)
        bar = "#" * c
        print(f"  {sid}: {c:2d}  {bar}")
    used = sum(1 for v in hits.values() if v)
    print(f"  → 实际用到的后端数：{used} / 3")

    ch.close()
    for s, _ in servers:
        s.stop(0)


PORTS = [0, 0, 0]

print("=" * 64)
print("gRPC 的负载均衡粒度：per-connection 还是 per-call")
print("=" * 64)

run(PORTS, [], 12, "默认策略（pick_first）")
run(PORTS, ROUND_ROBIN_OPTS, 12, "round_robin")

print("""
判读：
  · pick_first 只连第一个能连上的地址，之后所有请求都发到那里 → 3 个后端只用了 1 个
  · round_robin 每次调用换一个后端 → 3 个都用上，且次数几乎均分
  · 如果 gRPC 是按连接分的，round_robin 也只会用 1 个（一条连接只对应一个后端）
""")
