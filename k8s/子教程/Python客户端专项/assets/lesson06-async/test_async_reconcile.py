"""验证 1：异步调谐循环能否跑通课 6 的全部结论

对照课 6 第五幕的实测输出：
    informer 事件: ADDED rc-0/1/2, MODIFIED rc-0/1/2
    调谐统计: {'reconciled': 3, 'no_op': 3, 'errors': 0}

异步版要达到同样效果，且额外的：多 worker 并发 patch 不产生 409
"""
import asyncio
import sys
import time

sys.path.insert(0, "/mnt/d/projects/learning/k8s/子教程/Python客户端专项/assets/lesson06-async")

import kubernetes_asyncio as ka
from kubernetes_asyncio.client import ApiClient, CoreV1Api

from async_controller import AsyncController

NS = "py-lesson06-async"


async def setup(v1):
    try:
        await v1.create_namespace(body={"metadata": {"name": NS}})
        print(f"  创建 ns {NS}")
    except Exception as e:
        print(f"  ns: {type(e).__name__}")


async def cleanup(v1):
    try:
        await v1.delete_namespace(name=NS)
        print(f"  已删除 ns {NS}")
    except Exception as e:
        print(f"  删除: {type(e).__name__}")


async def main():
    await ka.config.load_kube_config()
    async with ApiClient() as api:
        v1 = CoreV1Api(api)
        await setup(v1)

        print("\n" + "=" * 70)
        print("验证 1：异步调谐循环 —— 对照课 6 第五幕")
        print("=" * 70)

        ctrl = AsyncController(api, NS, workers=4, concurrency=10)
        run_task = asyncio.create_task(ctrl.run(duration=None))

        await asyncio.sleep(0.8)   # 等 informer 起来

        # 创建 3 个 ConfigMap（对应课 6 的 rc-0/1/2）
        print("\n  创建 3 个 ConfigMap...")
        for i in range(3):
            await v1.create_namespaced_config_map(
                namespace=NS,
                body={"metadata": {"name": f"rc-{i}"}, "data": {"k": "v"}})
        print("  已创建，等待调谐...\n")

        await asyncio.sleep(3.0)
        await ctrl.shutdown()
        await run_task

        print("  informer 事件:")
        for et, name in ctrl.informer.events:
            print(f"      {et:<9} {name}")
        print(f"\n  调谐统计: {dict(ctrl.stats)}")
        print(f"  队列: added={ctrl.queue.added} dropped={ctrl.queue.dropped}")

        # 验证结果
        print("\n  最终状态:")
        r = await v1.list_namespaced_config_map(namespace=NS)
        for o in r.items:
            print(f"      {o.metadata.name}.data = {o.data}")

        print()
        print("=" * 70)
        print("判定")
        print("=" * 70)
        s = ctrl.stats
        print(f"  reconciled = {s['reconciled']}  (课 6 同步版: 3)")
        print(f"  no_op      = {s['no_op']}  (课 6 同步版: 3)")
        print(f"  errors     = {s['errors']}  (课 6 同步版: 0)")
        if s["errors"] == 0:
            print("  -> 多 worker 并发 patch，errors=0：无 409（patch 天然避开乐观锁）")
        else:
            print(f"  !! 有 {s['errors']} 个错误")

        await cleanup(v1)


asyncio.run(main())
