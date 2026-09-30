"""诊断：为什么只调谐了 rc-0，rc-1/rc-2 漏了？

假设清单（逐个证伪）：
  H1: watch 流断了（只收到 1 个 ADDED 就停了）
  H2: worker 提前退出（wait_for 超时后 continue，但 stop 已置位）
  H3: 队列去重把 rc-1/rc-2 丢了
  H4: patch 触发的 MODIFIED 没被 watch 到

方法：在关键点打时间戳，看每个环节到底发生了什么
"""
import asyncio
import sys
import time

sys.path.insert(0, "/mnt/d/projects/learning/k8s/子教程/Python客户端专项/assets/lesson06-async")

import kubernetes_asyncio as ka
from kubernetes_asyncio.client import ApiClient, CoreV1Api

NS = "py-lesson06-diag"
T0 = time.time()


def log(msg):
    print(f"  [{time.time()-T0:5.2f}s] {msg}")


async def main():
    await ka.config.load_kube_config()
    async with ApiClient() as api:
        v1 = CoreV1Api(api)
        try:
            await v1.create_namespace(body={"metadata": {"name": NS}})
        except Exception:
            pass

        print("=" * 70)
        print("诊断 A：裸 watch 能收到几个事件？")
        print("=" * 70)

        w = ka.watch.Watch()
        received = []

        async def watcher():
            async with w:
                async for e in w.stream(v1.list_namespaced_config_map,
                                        namespace=NS, timeout_seconds=2,
                                        _request_timeout=5):
                    received.append((e["type"], e["object"].metadata.name))
                    log(f"watch 收到 {e['type']:<9} {e['object'].metadata.name}")

        wt = asyncio.create_task(watcher())
        await asyncio.sleep(0.5)

        log("创建 3 个 ConfigMap")
        for i in range(3):
            await v1.create_namespaced_config_map(
                namespace=NS,
                body={"metadata": {"name": f"d-{i}"}, "data": {"k": "v"}})
            log(f"  已创建 d-{i}")

        await asyncio.sleep(3)
        wt.cancel()
        try:
            await wt
        except asyncio.CancelledError:
            pass

        log(f"裸 watch 共收到 {len(received)} 个事件: {received}")

        print()
        print("=" * 70)
        print("诊断 B：Watch.stream 耗尽后会怎样？")
        print("=" * 70)
        print("  课 6 同步版：for e in w.stream(...) 耗尽 → 外层 while 重新 stream")
        print("  异步版同理，但要看 stream 是每次新建连接还是复用")
        w2 = ka.watch.Watch()
        rounds = 0
        async with w2:
            for _ in range(3):
                rounds += 1
                cnt = 0
                async for e in w2.stream(v1.list_namespaced_config_map,
                                         namespace=NS, timeout_seconds=1,
                                         _request_timeout=5):
                    cnt += 1
                log(f"  第 {rounds} 轮 stream 结束，本轮 {cnt} 个事件")
        print(f"  -> async for 正常耗尽 {rounds} 轮，说明超时退休机制在异步下同样工作")

        print()
        print("=" * 70)
        print("诊断 C：worker 的 wait_for 行为")
        print("=" * 70)
        print("  reconcile_worker 里：await asyncio.wait_for(queue.get(), timeout=0.3)")
        print("  若 0.3s 内没任务 -> TimeoutError -> continue -> 再等")
        print("  这看起来没问题，但要确认 worker 不会因为 stop_event 之外的原因退出")

        q = asyncio.Queue()
        stopped = {"n": 0}

        async def worker(wid):
            while True:
                try:
                    await asyncio.wait_for(q.get(), timeout=0.3)
                except asyncio.TimeoutError:
                    continue
                except asyncio.CancelledError:
                    stopped["n"] += 1
                    raise

        ws = [asyncio.create_task(worker(i)) for i in range(4)]
        await asyncio.sleep(1.0)
        alive = sum(1 for t in ws if not t.done())
        print(f"  空转 1 秒后存活 worker: {alive}/4  (应为 4)")
        for t in ws:
            t.cancel()
        await asyncio.gather(*ws, return_exceptions=True)

        print()
        print("=" * 70)
        print("诊断 D：复现原问题 —— 加上 patch 触发 MODIFIED")
        print("=" * 70)
        print("  关键差异：调谐会 patch，patch 又触发 MODIFIED 事件")
        print("  如果 watch 在第 1 轮 stream 后就不再续接，后续事件全漏")

        try:
            await v1.delete_namespace(name=NS)
            print(f"\n  已清理 ns {NS}")
        except Exception as e:
            print(f"  清理: {type(e).__name__}")


asyncio.run(main())
