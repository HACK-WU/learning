"""Q3 补做：延长窗口，确证「重入队有上限、最终会放弃」

上一轮 dropped=0，判定写的是"未触发上限"。
这可能是缺陷，也可能只是**测试窗口太短**（3 秒内退避还没跑满 6 次）。
不能凭猜——延长窗口实测。
"""
import asyncio
import sys
from collections import defaultdict

sys.path.insert(0, "/mnt/d/projects/learning/k8s/子教程/Python客户端专项/assets/lesson06-async")

from kubernetes_asyncio.client.rest import ApiException

from retry_backoff import RetryPolicy, RetryQueue, classify, retry_async

NS = "py-lesson06-retry3"


async def main():
    print("=" * 70)
    print("Q3 补做：重入队上限是否真的会被触发")
    print("=" * 70)

    # 用很小的退避，让 6 次上限在短时间内跑完
    pol = RetryPolicy(max_attempts=1, base=0.02, cap=0.05)
    q = RetryQueue(policy=pol, max_requeues=3)      # 上限 3 次
    st = defaultdict(int)
    stop = asyncio.Event()
    sem = asyncio.Semaphore(4)
    calls = defaultdict(int)

    async def worker(wid):
        while not stop.is_set():
            try:
                n = await asyncio.wait_for(q.get(), timeout=0.15)
            except asyncio.TimeoutError:
                continue
            except asyncio.CancelledError:
                raise
            attempt = q.attempt_of(n)

            async def _f():
                calls[n] += 1
                raise ApiException(status=503, reason="Unavailable")

            requeued = False
            try:
                async with sem:
                    await retry_async(_f, pol, st)
            except asyncio.CancelledError:
                raise
            except Exception as e:
                if classify(e) == "retryable":
                    await q.requeue_after(n, pol.delay(attempt))
                    requeued = True
            if requeued:
                q.task_done(n)
            else:
                q.done(n)
            st["processed"] += 1

    for i in range(4):
        q.add(f"obj-{i}")
    ws = [asyncio.create_task(worker(i)) for i in range(3)]
    await asyncio.sleep(4.0)
    stop.set()
    for w in ws:
        w.cancel()
    await asyncio.gather(*ws, return_exceptions=True)
    await q.shutdown()

    print(f"\n  4 个持续失败对象，max_requeues=3，观察 4 秒\n")
    print(f"  {'对象':<10} {'调用次数':<10}")
    for k in sorted(calls):
        print(f"  {k:<10} {calls[k]:<10}")
    print()
    print(f"  队列 stats: {dict(q.stats)}")
    print(f"  重试 stats: {dict(st)}")
    print()
    dropped = q.stats.get("dropped_max_requeues", 0)
    requeued = q.stats.get("requeued", 0)
    total_calls = sum(calls.values())

    print(f"  判定:")
    print(f"    1. 重入队发生: {'✓' if requeued > 0 else '!! 无'} (requeued={requeued})")
    print(f"    2. 上限被触发: {'✓ 会放弃' if dropped > 0 else '!! 仍为 0'}"
          f" (dropped={dropped})")
    print(f"    3. 调用有界: 每对象 {total_calls/4:.1f} 次（上限 1+3=4 次/对象）")
    print()
    if dropped > 0:
        print("  → 上一轮 dropped=0 是**测试窗口太短**所致，非实现缺陷。")
        print("    缩短退避后 4 秒内即触发上限，失败对象被**有界地**放弃。")


asyncio.run(main())
