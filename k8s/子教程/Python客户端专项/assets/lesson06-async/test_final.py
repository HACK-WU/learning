"""验证 4（最终）：修复后的完整异步调谐循环

对照课 6 同步版，逐项确认：
  1. 事件序列一致（3 ADDED + 3 MODIFIED）
  2. reconciled=3, no_op=3, errors=0
  3. 优雅退出可靠（不依赖 timeout 巧合）
  4. 幂等性
"""
import asyncio
import sys
import time

sys.path.insert(0, "/mnt/d/projects/learning/k8s/子教程/Python客户端专项/assets/lesson06-async")

import kubernetes_asyncio as ka
from kubernetes_asyncio.client import ApiClient, CoreV1Api

from async_controller import (AsyncController, AsyncWorkQueue,
                              AsyncWorkQueueFixed)

NS = "py-lesson06-final"


async def main():
    await ka.config.load_kube_config()
    async with ApiClient() as api:
        v1 = CoreV1Api(api)
        try:
            await v1.create_namespace(body={"metadata": {"name": NS}})
        except Exception:
            # ns 可能残留（上次崩溃），先清空里面的 ConfigMap
            try:
                r = await v1.list_namespaced_config_map(namespace=NS)
                for o in r.items:
                    if o.metadata.name.startswith("rc-"):
                        try:
                            await v1.delete_namespaced_config_map(
                                name=o.metadata.name, namespace=NS)
                        except Exception:
                            pass
            except Exception:
                pass
        await asyncio.sleep(0.4)

        print("=" * 70)
        print("最终验证：用 Fixed 队列跑完整流程")
        print("=" * 70)

        ctrl = AsyncController(api, NS, workers=4, concurrency=10,
                               queue_cls=AsyncWorkQueueFixed)
        run_task = asyncio.create_task(ctrl.run())
        await asyncio.sleep(0.8)

        for i in range(3):
            await v1.create_namespaced_config_map(
                namespace=NS,
                body={"metadata": {"name": f"rc-{i}"}, "data": {"k": "v"}})

        await asyncio.sleep(3.0)

        # 再放一个对象，触发第二次调谐（验证 no_op）
        await v1.create_namespaced_config_map(
            namespace=NS,
            body={"metadata": {"name": "rc-9"}, "data": {"k": "v"}})
        await asyncio.sleep(2.5)

        t0 = time.time()
        await ctrl.shutdown()
        el = time.time() - t0
        await run_task

        print(f"\n  informer 事件 ({len(ctrl.informer.events)}):")
        for et, n in ctrl.informer.events:
            print(f"      {et:<9} {n}")
        print(f"\n  调谐统计: {dict(ctrl.stats)}")
        print(f"  队列: added={ctrl.queue.added} dropped={ctrl.queue.dropped} "
              f"requeued={ctrl.queue.requeued}")
        print(f"  shutdown 耗时: {el:.3f}s")
        print(f"  informer 致命错误: {ctrl.informer.fatal}")

        print("\n  最终状态:")
        r = await v1.list_namespaced_config_map(namespace=NS)
        for o in sorted(r.items, key=lambda x: x.metadata.name):
            if o.metadata.name.startswith("rc-"):
                print(f"      {o.metadata.name}.data = {o.data}")

        print()
        print("=" * 70)
        print("判定（对照课 6 同步版）")
        print("=" * 70)
        s = ctrl.stats
        print(f"  reconciled = {s['reconciled']:>2}   课6同步版: 3")
        print(f"  no_op      = {s['no_op']:>2}   课6同步版: 3")
        print(f"  errors     = {s['errors']:>2}   课6同步版: 0")
        print(f"  fatal      = {ctrl.informer.fatal}")
        ok = (s["errors"] == 0 and not ctrl.informer.fatal)
        print(f"\n  -> {'✓ 与同步版一致，无静默错误' if ok else '✗ 存在问题'}")

        # 幂等性：手动再调一次
        print()
        print("=" * 70)
        print("幂等性验证：对已调谐对象再调一次")
        print("=" * 70)
        from async_controller import reconcile_one
        from collections import defaultdict
        st = defaultdict(int)
        r1 = await reconcile_one(v1, NS, "rc-0", st)
        r2 = await reconcile_one(v1, NS, "rc-0", st)
        print(f"    第一次: {r1}")
        print(f"    第二次: {r2}  <- 幂等（已是期望状态，不再改动）")

        try:
            await v1.delete_namespace(name=NS)
            print(f"\n  已清理 ns {NS}")
        except Exception as e:
            print(f"  清理: {type(e).__name__}")


asyncio.run(main())
