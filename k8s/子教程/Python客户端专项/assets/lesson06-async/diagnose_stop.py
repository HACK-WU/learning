"""诊断：只 stop.set() 就退出，到底是 stop 生效还是 stream 自然到期？

上一轮 1 秒内就结束了，但 timeout_seconds=2 —— 时间对不上，
说明"任务自己结束"可能是别的原因。必须排除测法干扰。

对照实验：
  A: 不 set stop，纯等 —— 看任务会不会自己结束（排除自然到期误判）
  B: set stop 后立刻检查 —— 看是否立即退出
  C: 把 timeout_seconds 调大到 30，再测 stop.set() —— 若仍能快速退出，
     才是 stop 真的生效
"""
import asyncio
import sys
import time

sys.path.insert(0, "/mnt/d/projects/learning/k8s/子教程/Python客户端专项/assets/lesson06-async")

import kubernetes_asyncio as ka
from kubernetes_asyncio.client import ApiClient, CoreV1Api

from async_controller import AsyncInformer, AsyncWorkQueueFixed

NS = "py-lesson06-stop"


async def setup(v1):
    try:
        await v1.create_namespace(body={"metadata": {"name": NS}})
    except Exception:
        pass
    await asyncio.sleep(0.4)


async def main():
    await ka.config.load_kube_config()
    async with ApiClient() as api:
        v1 = CoreV1Api(api)
        await setup(v1)

        print("=" * 70)
        print("A: 不设 stop，timeout_seconds=30，看任务会不会自己结束")
        print("=" * 70)
        stop = asyncio.Event()
        q = AsyncWorkQueueFixed()
        inf = AsyncInformer(v1.list_namespaced_config_map, NS, q)
        t = asyncio.create_task(inf.run(stop, timeout_seconds=30))
        await asyncio.sleep(1.0)
        print(f"  1 秒后任务 done? {t.done()}   (应为 False —— 还在 watch)")

        print()
        print("=" * 70)
        print("B: 设 stop，timeout_seconds=30，看多久退出")
        print("=" * 70)
        t0 = time.time()
        stop.set()
        try:
            await asyncio.wait_for(t, timeout=5.0)
            el = time.time() - t0
            print(f"  任务在 {el:.3f}s 后结束")
            if el < 1.0:
                print("  -> stop 生效很快（stream 超时退休后检查到 stop）")
            else:
                print("  -> 退出较慢，说明是等 stream 自然到期才退的")
        except asyncio.TimeoutError:
            print("  -> ✗ 5 秒都没退出！stop.set() 不足以唤醒卡在 await 的 watch")
            t.cancel()
            await asyncio.gather(t, return_exceptions=True)
            print("     cancel() 后退出")

        print()
        print("=" * 70)
        print("C: 关键对照 —— timeout_seconds 大 vs 小，stop 响应时间")
        print("=" * 70)
        for ts in (2, 10, 30):
            stop2 = asyncio.Event()
            q2 = AsyncWorkQueueFixed()
            inf2 = AsyncInformer(v1.list_namespaced_config_map, NS, q2)
            t2 = asyncio.create_task(inf2.run(stop2, timeout_seconds=ts))
            await asyncio.sleep(0.6)
            t0 = time.time()
            stop2.set()
            try:
                await asyncio.wait_for(t2, timeout=ts + 3)
                el = time.time() - t0
                print(f"  timeout_seconds={ts:<3}: stop 后 {el:.3f}s 退出")
            except asyncio.TimeoutError:
                print(f"  timeout_seconds={ts:<3}: {ts+3}s 内未退出 ✗")
                t2.cancel()
                await asyncio.gather(t2, return_exceptions=True)

        print()
        print("=" * 70)
        print("判定")
        print("=" * 70)
        print("  若退出耗时 ≈ timeout_seconds -> 说明 stop 只是'下次 stream 到期时才发现'")
        print("  若退出耗时 ≈ 0               -> 说明 stop 真的能立即打断")
        print()
        print("  预期：耗时 ≈ timeout_seconds（因为 watch 卡在 await 网络读上）")
        print("  结论：生产代码必须 cancel()，不能只依赖 Event")

        try:
            await v1.delete_namespace(name=NS)
            print(f"\n  已清理 ns {NS}")
        except Exception as e:
            print(f"  清理: {type(e).__name__}")


asyncio.run(main())
