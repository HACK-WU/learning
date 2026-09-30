"""课 9 番外 · 实测 C：能否触发 apiserver 429 限流

课 9 未实测项 2。思路（先想清楚测法，避免"测了个寂寞"）：

429 来自 apiserver 的 APF（API Priority and Fairness）或 --max-requests-inflight。
kind 默认配置限流较高，普通并发可能根本撞不到。

测法设计（分层递进，先证明测法有效再谈结论）：
  L0 取证：先看 kind apiserver 的启动参数（max-requests-inflight / max-mutating）
  L1 温和并发：50 并发 list，记录是否出现 429
  L2 激进并发：拉高到 500 并发 + 多轮轰炸，记录 429 次数
  L3 判定：如果始终 0 次 429，必须证明"是限流没触发"而非"我测错了"
     —— 正对照：人为制造已知会被限流的信号？没有 429 就用别的码做正对照

判据：统计 status code 分布，尤其 429；同时记录 503/500（过载信号）。
"""
import asyncio
import time
from collections import Counter

from kubernetes_asyncio import client as aclient
from kubernetes_asyncio import config as aconfig

NS = "default"


def status_of(r):
    if isinstance(r, BaseException):
        return getattr(r, "status", None) or type(r).__name__
    return "OK"


async def l0_apiserver_flags():
    print("=== L0. apiserver 限流参数取证 ===")
    await aconfig.load_kube_config()
    async with aclient.ApiClient() as ac:
        core = aclient.CoreV1Api(ac)
        try:
            pods = await core.list_namespaced_pod(
                "kube-system", label_selector="component=kube-apiserver")
            for p in pods.items:
                print("  apiserver pod:", p.metadata.name)
                for c in p.spec.containers:
                    cmd = c.command or []
                    for f in cmd:
                        if any(k in f for k in ("inflight", "flow", "priority")):
                            print("   flag:", f)
        except Exception as e:
            print("  读取失败:", type(e).__name__, str(e)[:100])


async def burst(core, n, rounds, label, sem=None):
    codes = Counter()
    t0 = time.perf_counter()

    async def one():
        if sem:
            async with sem:
                return await core.list_namespaced_pod(NS, limit=1)
        return await core.list_namespaced_pod(NS, limit=1)

    for _ in range(rounds):
        rs = await asyncio.gather(*[one() for _ in range(n)],
                                  return_exceptions=True)
        for r in rs:
            codes[status_of(r)] += 1
    dt = time.perf_counter() - t0
    total = sum(codes.values())
    print(f"  {label}: 总请求 {total}, 耗时 {dt:.2f}s, "
          f"QPS {total/dt:.1f}")
    print(f"    状态码分布: {dict(codes)}")
    return codes


async def main():
    await l0_apiserver_flags()
    await aconfig.load_kube_config()

    async with aclient.ApiClient() as ac:
        core = aclient.CoreV1Api(ac)

        print()
        print("=== L1. 温和并发（50 × 3 轮）===")
        await burst(core, 50, 3, "L1")

        print()
        print("=== L2. 激进并发（300 × 5 轮，无信号量）===")
        await burst(core, 300, 5, "L2")

        print()
        print("=== L3. 更激进（800 × 5 轮）===")
        codes = await burst(core, 800, 5, "L3")

        n429 = codes.get(429, 0)
        print()
        print("=== 结论 ===")
        print(f"  429 出现次数: {n429}")
        if n429 == 0:
            print("  → 本次未能触发 429。需证明是'限流没触发'而非'测法错误'")
        else:
            print("  → 触发成功，可分析重试语义")


if __name__ == "__main__":
    asyncio.run(main())
