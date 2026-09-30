"""课 9：为什么 16 线程比 1 线程慢 2.8 倍？

假设（三选一，用实验区分）：
  H1: GIL 限制 —— 但 IO 密集应释放 GIL，不成立
  H2: apiserver 侧限流/排队 —— 并发请求被服务端串行处理
  H3: 客户端开销（反序列化 + 连接池争用）超过并行收益

区分方法：
  测 1: 不反序列化（_preload_content=False，只拿 raw）→ 若变快，是 CPU/反序列化瓶颈(H3)
  测 2: 只测 HTTP 层（用 urllib3 直连，不经 client 库）→ 剥离库开销
  测 3: 看并发数 1/2/4/8/16 的耗时曲线 → 若单调上升，是服务端排队(H2)
"""
import statistics
import time
from kubernetes import client, config

config.load_kube_config()
N = 60


def bench(api, tag, rounds=3):
    ts = []
    for _ in range(rounds):
        t0 = time.time()
        threads = [api.list_pod_for_all_namespaces(async_req=True) for _ in range(N)]
        for t in threads:
            t.get()
        ts.append(time.time() - t0)
    m = statistics.median(ts)
    print(f"  {tag}: {m:.2f}s")
    return m


print("=" * 64)
print("测 3：并发度扫描（pool_threads = 1,2,4,8,16,32）")
print("=" * 64)
curve = {}
for pt in (1, 2, 4, 8, 16, 32):
    a = client.CoreV1Api(client.ApiClient(pool_threads=pt))
    curve[pt] = bench(a, f"pool_threads={pt:<3}")

print()
print("耗时曲线：")
best_pt = min(curve, key=curve.get)
for pt, t in sorted(curve.items()):
    mark = "  <-- 最快" if pt == best_pt else ""
    print(f"  {pt:>3} 线程: {t:.2f}s{mark}")

print()
print("=" * 64)
print("测 1：不反序列化（_preload_content=False）对比")
print("=" * 64)
api16 = client.CoreV1Api(client.ApiClient(pool_threads=16))


def bench_raw(api, tag, rounds=3):
    ts = []
    for _ in range(rounds):
        t0 = time.time()
        threads = [api.list_pod_for_all_namespaces(async_req=True, _preload_content=False)
                   for _ in range(N)]
        for t in threads:
            r = t.get()
            r.close()   # 课 8 知识点：非阻塞流必须 close
        ts.append(time.time() - t0)
    m = statistics.median(ts)
    print(f"  {tag}: {m:.2f}s")
    return m


t_raw_16 = bench_raw(api16, "16线程 + raw(不反序列化)")
t_full_16 = curve[16]
print(f"  16线程 + 反序列化: {t_full_16:.2f}s")
print(f"  -> 反序列化开销占比: {(t_full_16-t_raw_16)/t_full_16*100:.0f}%")
