"""验证 10：重试与退避实测

考四件事（都必须实测）：
  Q1 效果：临时故障下，重试版能否最终调谐成功？（对比番外 1 的丢弃版）
  Q2 分类：404/422 是否被正确识别为「不重试」？（不浪费额度）
  Q3 阻塞：重试版是否避免了队头阻塞？（对比天真重试的 3 秒 30 次）
  Q4 惊群：jitter 是否真的打散了重试时刻？
"""
import asyncio
import random
import sys
import time
from collections import defaultdict

sys.path.insert(0, "/mnt/d/projects/learning/k8s/子教程/Python客户端专项/assets/lesson06-async")

import kubernetes_asyncio as ka
from kubernetes_asyncio.client import ApiClient, CoreV1Api
from kubernetes_asyncio.client.rest import ApiException

from async_controller import AsyncWorkQueueFixed, reconcile_one
from retry_backoff import (RetryPolicy, RetryQueue, backoff_delay, classify,
                           reconcile_worker_retry, retry_async)

NS = "py-lesson06-retry2"


async def setup(v1, n=6):
    try:
        await v1.create_namespace(body={"metadata": {"name": NS}})
    except Exception:
        pass
    await asyncio.sleep(0.4)
    for i in range(n):
        try:
            await v1.create_namespaced_config_map(
                namespace=NS,
                body={"metadata": {"name": f"rb-{i}"}, "data": {"k": "v"}})
        except Exception:
            pass
    await asyncio.sleep(0.5)


async def cleanup(v1):
    try:
        r = await v1.list_namespaced_config_map(namespace=NS)
        for o in r.items:
            await v1.delete_namespaced_config_map(o.metadata.name, NS)
    except Exception:
        pass


# ---------------------------------------------------------------- Q1

async def q1_transient():
    print("=" * 70)
    print("Q1 效果：临时故障下能否最终成功？")
    print("=" * 70)

    await ka.config.load_kube_config()
    async with ApiClient() as api:
        v1 = CoreV1Api(api)
        await setup(v1)

        # 模拟「前 2 次必然失败，第 3 次起成功」的临时故障
        state = defaultdict(int)

        async def flaky():
            k = "probe"
            state[k] += 1
            if state[k] <= 2:
                raise ApiException(status=503, reason="Service Unavailable")
            return "ok"

        pol = RetryPolicy(max_attempts=5, base=0.05, cap=1.0)
        st = defaultdict(int)
        t0 = time.monotonic()
        r = await retry_async(flaky, pol, st)
        ok = True
        el = time.monotonic() - t0

        print(f"\n  注入：前 2 次返回 503，第 3 次成功")
        print(f"  结果: r={r!r} ok={ok}  实际调用 {state['probe']} 次")
        print(f"  耗时: {el:.3f}s   stats={dict(st)}")
        print()
        print(f"  判定: {'✓ 自动重试后成功' if ok and state['probe']==3 else '!! 失败'}")

        # 对照：番外 1 的丢弃版
        print()
        print("  对照（番外 1 的裸 except 丢弃版）:")
        state2 = defaultdict(int)

        async def flaky2():
            state2["p"] += 1
            raise ApiException(status=503, reason="Service Unavailable")

        lost = defaultdict(int)
        try:
            await flaky2()
        except Exception:
            lost["errors"] += 1
        print(f"    调用 {state2['p']} 次后 → stats={dict(lost)}")
        print(f"    → 对象被丢弃，**后续再也不会被调谐** = 永久状态漂移")


# ---------------------------------------------------------------- Q2

async def q2_classify():
    print()
    print("=" * 70)
    print("Q2 分类：404/422 是否被判为「不重试」")
    print("=" * 70)

    cases = [
        (ApiException(status=404, reason="Not Found"), "gone"),
        (ApiException(status=422, reason="Unprocessable"), "fatal"),
        (ApiException(status=400, reason="Bad Request"), "fatal"),
        (ApiException(status=409, reason="Conflict"), "retryable"),
        (ApiException(status=503, reason="Unavailable"), "retryable"),
        (asyncio.TimeoutError(), "retryable"),
        (RuntimeError("未知"), "fatal"),
    ]
    print(f"\n  {'异常':<34} {'分类':<12} 判定")
    print(f"  {'-'*34} {'-'*12} {'-'*6}")
    ok = True
    for e, want in cases:
        got = classify(e)
        mark = "OK" if got == want else "!!"
        ok &= (got == want)
        print(f"  {str(e)[:34]:<34} {got:<12} {mark}")

    print()
    print(f"  {'✓ 分类全部正确' if ok else '!! 有分类错误'}")

    # 实测：404 是否真的只调用 1 次（不浪费额度）
    print()
    print("  验证：404 只调用 1 次就放弃（不重试）")
    cnt = defaultdict(int)

    async def always404():
        cnt["n"] += 1
        raise ApiException(status=404, reason="Not Found")

    st = defaultdict(int)
    try:
        await retry_async(always404, RetryPolicy(max_attempts=5, base=0.05), st)
    except ApiException:
        pass
    print(f"    实际调用次数 = {cnt['n']}  stats={dict(st)}")
    print(f"    → {'✓ 1 次即放弃' if cnt['n'] == 1 else '!! 浪费了重试额度'}")


# ---------------------------------------------------------------- Q3

async def q3_no_blocking():
    print()
    print("=" * 70)
    print("Q3 阻塞：重试版是否避免队头阻塞？")
    print("=" * 70)

    await ka.config.load_kube_config()
    async with ApiClient() as api:
        v1 = CoreV1Api(api)
        await setup(v1, n=6)

        calls = defaultdict(int)

        async def always_fail():
            calls["t"] += 1
            raise ApiException(status=503, reason="Unavailable")

        # --- 天真版：worker 在重试循环里 sleep ---
        q1 = AsyncWorkQueueFixed()
        st1 = defaultdict(int)
        stop = asyncio.Event()

        async def naive_worker():
            while not stop.is_set():
                try:
                    n = await asyncio.wait_for(q1.get(), timeout=0.2)
                except asyncio.TimeoutError:
                    continue
                try:
                    for _ in range(1000):
                        try:
                            await always_fail()
                            break
                        except Exception:
                            calls["naive"] += 1
                            await asyncio.sleep(0.1)
                finally:
                    q1.done(n)

        for i in range(6):
            q1.add(f"rb-{i}")
        t = asyncio.create_task(naive_worker())
        await asyncio.sleep(3.0)
        stop.set()
        t.cancel()
        try:
            await t
        except asyncio.CancelledError:
            pass
        naive_calls = calls["naive"]

        # --- 重试队列版：失败延迟重入队，worker 不等待 ---
        pol = RetryPolicy(max_attempts=3, base=0.3, cap=2.0)
        q2 = RetryQueue(policy=pol, max_requeues=6)
        st2 = defaultdict(int)
        stop2 = asyncio.Event()
        sem = asyncio.Semaphore(4)

        async def smart_worker(wid):
            while not stop2.is_set():
                try:
                    n = await asyncio.wait_for(q2.get(), timeout=0.2)
                except asyncio.TimeoutError:
                    continue
                except asyncio.CancelledError:
                    raise
                attempt = q2.attempt_of(n)

                async def _f():
                    calls["smart"] += 1
                    raise ApiException(status=503, reason="Unavailable")

                requeued = False
                try:
                    async with sem:
                        await retry_async(_f, pol, st2)
                except asyncio.CancelledError:
                    raise
                except Exception as e:
                    if classify(e) == "retryable":
                        await q2.requeue_after(n, pol.delay(attempt))
                        requeued = True
                if requeued:
                    q2.task_done(n)
                else:
                    q2.done(n)

        for i in range(6):
            q2.add(f"rb-{i}")
        ws = [asyncio.create_task(smart_worker(i)) for i in range(3)]
        await asyncio.sleep(3.0)
        stop2.set()
        for w in ws:
            w.cancel()
        await asyncio.gather(*ws, return_exceptions=True)
        await q2.shutdown()
        smart_calls = calls["smart"]

        print(f"\n  6 个持续失败的对象，3 秒窗口：")
        print(f"    天真版（worker 内 sleep）: {naive_calls} 次调用")
        print(f"    重试队列版（延迟重入队）  : {smart_calls} 次调用")
        print(f"    → 退避让调用次数下降 {naive_calls - smart_calls} 次 "
              f"({(1 - smart_calls/max(naive_calls,1)) * 100:.0f}%)")
        print()
        print(f"  重试队列 stats: {dict(q2.stats)}")
        print(f"    done_first_try={q2.stats.get('done_first_try', 0)} "
              f"requeued={q2.stats.get('requeued', 0)} "
              f"dropped={q2.stats.get('dropped_max_requeues', 0)}")
        print()
        print(f"  判定: {'✓ 有上限、会放弃' if q2.stats.get('dropped_max_requeues', 0) > 0 else '!! 未触发上限'}")


# ---------------------------------------------------------------- Q4

async def q4_thundering():
    print()
    print("=" * 70)
    print("Q4 惊群：jitter 是否打散重试时刻")
    print("=" * 70)

    N = 100
    print(f"\n  {N} 个对象同时失败，观测第 3 次重试的时刻分布\n")
    print(f"  {'jitter':<14} {'跨度(s)':<12} {'min':<8} {'max':<8} 判定")
    print(f"  {'-'*14} {'-'*12} {'-'*8} {'-'*8} {'-'*10}")

    for j in ("none", "full", "equal"):
        random.seed(42)
        ts = []
        for _ in range(N):
            t = backoff_delay(0, 0.1, 5.0, j) + backoff_delay(1, 0.1, 5.0, j) \
                + backoff_delay(2, 0.1, 5.0, j)
            ts.append(t)
        span = max(ts) - min(ts)
        verdict = "惊群！" if span < 1e-9 else "已打散"
        print(f"  {j:<14} {span:<12.4f} {min(ts):<8.3f} {max(ts):<8.3f} {verdict}")

    print()
    print("  → none 时跨度恒为 0：100 个请求**同一瞬间**打到 apiserver")
    print("    equal/full 把请求摊平到半个退避窗口内")


# ---------------------------------------------------------------- Q5 端到端

async def q5_e2e():
    print()
    print("=" * 70)
    print("Q5 端到端：真实调谐 + 注入临时故障")
    print("=" * 70)

    await ka.config.load_kube_config()
    async with ApiClient() as api:
        v1 = CoreV1Api(api)
        await setup(v1, n=5)
        await cleanup(v1)
        for i in range(5):
            await v1.create_namespaced_config_map(
                namespace=NS,
                body={"metadata": {"name": f"rb-{i}"}, "data": {"k": "v"}})
        await asyncio.sleep(0.5)

        # 注入：让 patch 前两次抛 503
        orig_patch = v1.patch_namespaced_config_map
        state = defaultdict(int)

        async def flaky_patch(*a, **kw):
            state["c"] += 1
            if state["c"] <= 6:                  # 前 6 次调用失败
                raise ApiException(status=503, reason="Unavailable")
            return await orig_patch(*a, **kw)

        v1.patch_namespaced_config_map = flaky_patch

        pol = RetryPolicy(max_attempts=4, base=0.1, cap=1.0)
        q = RetryQueue(policy=pol, max_requeues=6)
        stats = defaultdict(int)
        stop = asyncio.Event()
        sem = asyncio.Semaphore(3)

        async def worker(wid):
            while not stop.is_set():
                try:
                    n = await asyncio.wait_for(q.get(), timeout=0.2)
                except asyncio.TimeoutError:
                    continue
                except asyncio.CancelledError:
                    raise
                attempt = q.attempt_of(n)

                async def _f():
                    return await reconcile_one(v1, NS, n, stats)

                requeued = False
                try:
                    async with sem:
                        await retry_async(_f, pol, stats)
                    stats["ok"] += 1
                except asyncio.CancelledError:
                    raise
                except Exception as e:
                    if classify(e) == "retryable":
                        stats["failed_final"] += 1
                        await q.requeue_after(n, pol.delay(attempt))
                        requeued = True
                if requeued:
                    q.task_done(n)
                    stats["requeued"] += 1
                else:
                    q.done(n)
                stats["processed"] += 1

        for i in range(5):
            q.add(f"rb-{i}")
        ws = [asyncio.create_task(worker(i)) for i in range(3)]
        await asyncio.sleep(8.0)
        stop.set()
        for w in ws:
            w.cancel()
        await asyncio.gather(*ws, return_exceptions=True)
        await q.shutdown()

        r = await v1.list_namespaced_config_map(namespace=NS)
        got = sorted((o.metadata.name, (o.data or {}).get("managed"))
                     for o in r.items if o.metadata.name.startswith("rb-"))
        n_ok = sum(1 for _, v in got if v == "true")
        print(f"\n  注入前 6 次 patch 返回 503，之后正常")
        print(f"  最终: {got}")
        print(f"  stats: {dict(stats)}")
        print(f"  队列: {dict(q.stats)}")
        print()
        print(f"  判定: {'✓ 5/5 最终调谐成功' if n_ok == 5 else f'!! 仅 {n_ok}/5'}")


async def main():
    await q1_transient()
    await q2_classify()
    await q3_no_blocking()
    await q4_thundering()
    await q5_e2e()

    await ka.config.load_kube_config()
    async with ApiClient() as api:
        try:
            await CoreV1Api(api).delete_namespace(name=NS)
            print(f"\n已清理 ns {NS}")
        except Exception as e:
            print(f"清理: {type(e).__name__}")


asyncio.run(main())
