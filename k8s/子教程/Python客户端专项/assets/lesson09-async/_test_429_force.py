"""逼出真 429（针对 Reject 型级别）

取证已明：
  - 我的请求落在 global-default（Queue 型，128 队列 / 上限 50）→ 排队而非拒绝
  - catch-all 是 Reject 型（nominal=5）→ 落到这里才可能 429

两条路逼出 429：
  R1. 把队列打爆：global-default 队列上限 50，持续高压让 queueLengthLimit 溢出
     —— 但 Queue 型溢出也可能仍是排队等待而非 429，需实测
  R2. 换身份打到 catch-all：用 ServiceAccount token（service-accounts → workload-low）
     —— workload-low 是 Queue 型，仍不拒绝
     —— 真正 Reject 的只有 catch-all，需匿名/未匹配任何 flowschema 的请求

更直接的思路（R3）：APF 之外还有一层 —— --max-requests-inflight（总量闸）
  kind apiserver 默认 max-requests-inflight=400 / max-mutating=200
  若并发 > 400 且瞬时全部在飞，理论上会 429

本次先做 R1（长时间持续压测，观察是否 429）+ R3（并发超过 inflight 上限）。
判据：任何 429 出现即成功；仍为 0 则记录环境结论。
"""
import asyncio
import time
from collections import Counter

from kubernetes_asyncio import config as aconfig
from kubernetes_asyncio import client as aclient

NS = "default"


async def r1_sustained(core, duration=8.0, concurrency=600):
    print("=== R1. 持续高压（8 秒 × 并发 600）===")
    codes = Counter()
    stop = asyncio.Event()
    started = time.perf_counter()

    async def worker():
        while not stop.is_set():
            try:
                await core.list_namespaced_pod(NS, limit=1)
                codes["OK"] += 1
            except Exception as e:
                codes[getattr(e, "status", None) or type(e).__name__] += 1

    tasks = [asyncio.create_task(worker()) for _ in range(concurrency)]
    await asyncio.sleep(duration)
    stop.set()
    await asyncio.gather(*tasks, return_exceptions=True)
    dt = time.perf_counter() - started
    total = sum(codes.values())
    print(f"  总请求 {total}, 耗时 {dt:.2f}s, QPS {total/dt:.1f}")
    print(f"  状态码分布: {dict(codes)}")
    return codes


async def r3_above_inflight(core, n=1200):
    print()
    print("=== R3. 瞬时并发超过 max-requests-inflight（1200 同时发起）===")
    t0 = time.perf_counter()
    rs = await asyncio.gather(
        *[core.list_namespaced_pod(NS, limit=1) for _ in range(n)],
        return_exceptions=True)
    dt = time.perf_counter() - t0
    codes = Counter()
    for r in rs:
        if isinstance(r, BaseException):
            codes[getattr(r, "status", None) or type(r).__name__] += 1
        else:
            codes["OK"] += 1
    print(f"  总请求 {len(rs)}, 耗时 {dt:.2f}s")
    print(f"  状态码分布: {dict(codes)}")
    return codes


async def r4_anon_to_catchall():
    print()
    print("=== R4. 匿名请求打到 catch-all（Reject 型）===")
    print("  说明：kind 默认关闭匿名访问（--anonymous-auth 可能 false）")
    cfg = aclient.Configuration()
    cfg.host = "https://127.0.0.1:6443"
    cfg.verify_ssl = False
    try:
        ac = aclient.ApiClient(cfg)
        core = aclient.CoreV1Api(ac)
        await core.list_namespaced_pod(NS, limit=1)
        print("  匿名访问: 竟然成功（匿名已开启）")
    except Exception as e:
        print(f"  匿名访问: {type(e).__name__}, status={getattr(e,'status',None)}")
        print("  → kind 默认拒绝匿名，无法用匿名打到 catch-all")
    finally:
        try:
            await ac.close()
        except Exception:
            pass


async def main():
    await aconfig.load_kube_config()
    cfg = aclient.Configuration.get_default_copy()
    cfg.max_pool_size = 1000
    ac = aclient.ApiClient(cfg)
    core = aclient.CoreV1Api(ac)
    try:
        c1 = await r1_sustained(core)
        c3 = await r3_above_inflight(core)
        await r4_anon_to_catchall()

        total429 = c1.get(429, 0) + c3.get(429, 0)
        print()
        print("=== 结论 ===")
        print(f"  429 总次数: {total429}")
        if total429 == 0:
            print("  → 环境级结论：本机 kind 集群在客户端可打出的量级下不触发 429")
            print("     原因：global-default 为 Queue 型（排队非拒绝），")
            print("           Reject 型的 catch-all 无法由正常身份命中")
    finally:
        await ac.close()


if __name__ == "__main__":
    asyncio.run(main())
