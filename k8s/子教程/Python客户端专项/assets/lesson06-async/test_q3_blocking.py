"""Q3 重写：队头阻塞的正确度量

🚨 上一版测法错误（本课程第五次）：
   我拿「3 秒内的总调用次数」当指标，天真版 30 vs 重试队列版 40，
   得出"下降 -33%"这种荒谬结论。

   错在哪：**调用次数根本不是队头阻塞的度量**。
   队头阻塞的定义是——**前面的坏任务挡住了后面的好任务**。
   正确度量应该是：混入坏对象后，**好对象还能不能被及时处理**。

   修复后重入队真正生效，调用变多恰恰说明重试在工作，
   拿它当"性能退化"是彻头彻尾的误诊。
"""
import asyncio
import sys
import time
from collections import defaultdict

sys.path.insert(0, "/mnt/d/projects/learning/k8s/子教程/Python客户端专项/assets/lesson06-async")

import kubernetes_asyncio as ka
from kubernetes_asyncio.client import ApiClient, CoreV1Api
from kubernetes_asyncio.client.rest import ApiException

from async_controller import AsyncWorkQueueFixed, reconcile_one
from retry_backoff import RetryPolicy, RetryQueue, classify, retry_async

NS = "py-lesson06-retry4"

BAD = {"b0", "b1"}          # 永远失败
GOOD = {"g0", "g1", "g2", "g3"}


async def setup(v1):
    try:
        await v1.create_namespace(body={"metadata": {"name": NS}})
    except Exception:
        pass
    await asyncio.sleep(0.4)
    for n in list(BAD) + list(GOOD):
        try:
            await v1.create_namespaced_config_map(
                namespace=NS,
                body={"metadata": {"name": n}, "data": {"k": "v"}})
        except Exception:
            pass
    await asyncio.sleep(0.5)


async def reset_good(v1):
    for n in GOOD:
        await v1.patch_namespaced_config_map(
            name=n, namespace=NS, body={"data": {"k": "v"}})


async def done_names(v1):
    r = await v1.list_namespaced_config_map(namespace=NS)
    return sorted(o.metadata.name for o in r.items
                  if (o.data or {}).get("managed") == "true")


async def run_naive(v1, seconds=6.0):
    """天真版：worker 在重试循环里 sleep"""
    q = AsyncWorkQueueFixed()
    stop = asyncio.Event()
    st = defaultdict(int)
    t_done = {}

    async def work():
        while not stop.is_set():
            try:
                n = await asyncio.wait_for(q.get(), timeout=0.2)
            except asyncio.TimeoutError:
                continue
            try:
                if n in BAD:                      # 坏对象：worker 内死循环重试
                    for _ in range(10000):
                        try:
                            raise ApiException(status=503, reason="x")
                        except Exception:
                            st["naive_calls"] += 1
                            await asyncio.sleep(0.1)
                else:                              # 好对象：正常调谐
                    await reconcile_one(v1, NS, n, st)
                    t_done[n] = time.monotonic()
            finally:
                q.done(n)

    for n in list(BAD) + list(GOOD):
        q.add(n)
    t = asyncio.create_task(work())
    t0 = time.monotonic()
    await asyncio.sleep(seconds)
    stop.set()
    t.cancel()
    try:
        await t
    except asyncio.CancelledError:
        pass
    return t_done, st, t0


async def run_smart(v1, seconds=6.0):
    """重试队列版：坏对象延迟重入队，worker 立刻去干别的"""
    pol = RetryPolicy(max_attempts=1, base=0.2, cap=1.0)
    q = RetryQueue(policy=pol, max_requeues=3)
    stop = asyncio.Event()
    sem = asyncio.Semaphore(3)
    st = defaultdict(int)
    t_done = {}

    async def work(wid):
        while not stop.is_set():
            try:
                n = await asyncio.wait_for(q.get(), timeout=0.2)
            except asyncio.TimeoutError:
                continue
            except asyncio.CancelledError:
                raise
            attempt = q.attempt_of(n)

            async def _f():
                if n in BAD:
                    st["smart_calls"] += 1
                    raise ApiException(status=503, reason="x")
                return await reconcile_one(v1, NS, n, st)

            requeued = False
            try:
                async with sem:
                    await retry_async(_f, pol, st)
                t_done[n] = time.monotonic()
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

    for n in list(BAD) + list(GOOD):
        q.add(n)
    ws = [asyncio.create_task(work(i)) for i in range(2)]
    t0 = time.monotonic()
    await asyncio.sleep(seconds)
    stop.set()
    for w in ws:
        w.cancel()
    await asyncio.gather(*ws, return_exceptions=True)
    await q.shutdown()
    return t_done, st, t0


async def main():
    print("=" * 70)
    print("Q3 重写：队头阻塞 = 坏对象是否挡住好对象")
    print("=" * 70)
    print("\n  场景：2 个永远失败的坏对象 + 4 个正常对象，"
          "**坏对象先入队**\n")

    await ka.config.load_kube_config()
    async with ApiClient() as api:
        v1 = CoreV1Api(api)
        await setup(v1)

        # ---- 天真版 ----
        await reset_good(v1)
        await asyncio.sleep(0.3)
        nd, ns_stat, n0 = await run_naive(v1)
        n_good_naive = len([k for k in nd if k in GOOD])
        n_time_naive = (max(nd.values()) - n0) if nd else float("inf")

        # ---- 重试队列版 ----
        await reset_good(v1)
        await asyncio.sleep(0.3)
        sd, ss_stat, s0 = await run_smart(v1)
        n_good_smart = len([k for k in sd if k in GOOD])
        n_time_smart = (max(sd.values()) - s0) if sd else float("inf")

        print(f"  {'方案':<22} {'好对象完成':<12} {'全部完成耗时':<14} 判定")
        print(f"  {'-'*22} {'-'*12} {'-'*14} {'-'*12}")
        print(f"  {'天真(worker内sleep)':<22} "
              f"{f'{n_good_naive}/4':<12} "
              f"{f'{n_time_naive:.2f}s' if n_time_naive != float('inf') else '未完成':<14} "
              f"{'队头阻塞' if n_good_naive < 4 else '未阻塞'}")
        print(f"  {'重试队列(延迟重入队)':<22} "
              f"{f'{n_good_smart}/4':<12} "
              f"{f'{n_time_smart:.2f}s' if n_time_smart != float('inf') else '未完成':<14} "
              f"{'✓ 正常' if n_good_smart == 4 else '!! 仍阻塞'}")

        print()
        print(f"  天真版 坏对象调用次数: {ns_stat.get('naive_calls', 0)}")
        print(f"  重试版 坏对象调用次数: {ss_stat.get('smart_calls', 0)}")
        print()
        print("  判定依据（**正确度量**）:")
        print("    队头阻塞 = 坏对象占死 worker，好对象排不上队")
        print("    → 看**好对象的完成数**，不是总调用次数")

        try:
            await v1.delete_namespace(name=NS)
            print(f"\n  已清理 ns {NS}")
        except Exception:
            pass


asyncio.run(main())
