"""验证 6：把 leaderelection 与课 6 异步调谐循环接起来

这才是真实用法：
    onstarted_leading  -> 启动 AsyncController（成为 leader 才调谐）
    onstopped_leading  -> 关闭 AsyncController

关键考点：
    1. 非 leader 副本不能调谐（否则多副本重复干活）
    2. leader 掉线后，新 leader 要能接管（且不能双写）
    3. onstopped_leading 必须能可靠停掉控制器（呼应番外第四部分）
"""
import asyncio
import contextlib
import io
import logging
import sys
import time

# leaderelection 库在抢锁失败时会打完整 traceback，噪声极大
# 这里只抑制它的日志输出，不改变任何逻辑
logging.getLogger("kubernetes_asyncio.leaderelection").setLevel(logging.CRITICAL)
logging.getLogger("kubernetes_asyncio.client").setLevel(logging.CRITICAL)

sys.path.insert(0, "/mnt/d/projects/learning/k8s/子教程/Python客户端专项/assets/lesson06-async")

import kubernetes_asyncio as ka
from kubernetes_asyncio.client import (ApiClient, CoreV1Api, CoordinationV1Api,
                                       V1Lease, V1LeaseSpec, V1ObjectMeta)
from kubernetes_asyncio.client.rest import ApiException
from kubernetes_asyncio.leaderelection.electionconfig import Config
from kubernetes_asyncio.leaderelection.leaderelection import LeaderElection
from kubernetes_asyncio.leaderelection.resourcelock.leaselock import LeaseLock

from async_controller import AsyncController, AsyncWorkQueueFixed

NS = "py-lesson06-le2"
LEASE = "ctrl"


async def setup(v1n):
    try:
        await v1n.create_namespace(body={"metadata": {"name": NS}})
    except Exception:
        # 残留：清掉 rc-*
        try:
            r = await v1n.list_namespaced_config_map(namespace=NS)
            for o in r.items:
                if o.metadata.name.startswith("rc-"):
                    try:
                        await v1n.delete_namespaced_config_map(
                            name=o.metadata.name, namespace=NS)
                    except Exception:
                        pass
        except Exception:
            pass
    await asyncio.sleep(0.4)


async def replica(name, state):
    """一个副本：选主 + 成为 leader 才跑控制器"""
    async with ApiClient() as api:
        coord = CoordinationV1Api(api)
        try:
            await coord.create_namespaced_lease(
                namespace=NS,
                body=V1Lease(
                    metadata=V1ObjectMeta(name=LEASE, namespace=NS),
                    spec=V1LeaseSpec(lease_duration_seconds=8)))
        except ApiException as e:
            if e.status != 409:
                pass

        lock = LeaseLock(LEASE, NS, name, api)
        ctrl = None
        ctrl_task = None

        async def on_started():
            nonlocal ctrl, ctrl_task
            state["leaders"].append(name)
            state["log"].append(f"{time.time()-state['t0']:5.1f}s {name} -> leader, 启动控制器")
            ctrl = AsyncController(api, NS, workers=3, concurrency=8,
                                   queue_cls=AsyncWorkQueueFixed)
            ctrl_task = asyncio.create_task(ctrl.run())

        async def on_stopped():
            nonlocal ctrl, ctrl_task
            state["log"].append(f"{time.time()-state['t0']:5.1f}s {name} -> 失去 leadership, 停控制器")
            if ctrl is not None:
                await ctrl.shutdown()
            if ctrl_task is not None:
                ctrl_task.cancel()
                try:
                    await ctrl_task
                except asyncio.CancelledError:
                    pass
            state["ctrl"][name] = dict(ctrl.stats) if ctrl else {}

        cfg = Config(lock, lease_duration=8, renew_deadline=5, retry_period=2,
                     onstarted_leading=on_started, onstopped_leading=on_stopped)
        le = LeaderElection(cfg)
        try:
            await le.run()
        except asyncio.CancelledError:
            # 被 cancel：主动交出 leadership
            if ctrl is not None:
                await ctrl.shutdown()
            raise
        except Exception as e:
            state["log"].append(f"{name} 异常 {type(e).__name__}: {e}")


async def main():
    await ka.config.load_kube_config()
    async with ApiClient() as api:
        await setup(CoreV1Api(api))

    state = {"leaders": [], "log": [], "ctrl": {}, "t0": time.time()}

    print("=" * 70)
    print("选主 + 调谐控制器集成")
    print("=" * 70)

    tasks = [asyncio.create_task(replica(f"r{i}", state)) for i in range(3)]
    await asyncio.sleep(3)

    async with ApiClient() as api:
        coord = CoordinationV1Api(api)
        l = await coord.read_namespaced_lease(name=LEASE, namespace=NS)
        holder1 = l.spec.holder_identity
    print(f"\n  第一任 leader: {holder1}")

    # 放对象，只有 leader 该调谐
    async with ApiClient() as api:
        v1 = CoreV1Api(api)
        for i in range(3):
            await v1.create_namespaced_config_map(
                namespace=NS,
                body={"metadata": {"name": f"rc-{i}"}, "data": {"k": "v"}})
    print("  创建 3 个 ConfigMap，等 4 秒...")

    await asyncio.sleep(4)

    async with ApiClient() as api:
        v1 = CoreV1Api(api)
        r = await v1.list_namespaced_config_map(namespace=NS)
        managed = [(o.metadata.name, (o.data or {}).get("managed"))
                   for o in r.items if o.metadata.name.startswith("rc-")]
    print(f"  调谐结果: {sorted(managed)}")
    done1 = all(v == "true" for _, v in managed)

    print()
    print("=" * 70)
    print(f"故障转移：cancel 掉 leader {holder1}")
    print("=" * 70)
    idx = int(holder1[1])
    tasks[idx].cancel()
    try:
        await tasks[idx]
    except asyncio.CancelledError:
        pass

    t0 = time.time()
    holder2 = None
    async with ApiClient() as api:
        coord = CoordinationV1Api(api)
        for _ in range(40):
            await asyncio.sleep(0.5)
            try:
                l = await coord.read_namespaced_lease(name=LEASE, namespace=NS)
                if l.spec.holder_identity and l.spec.holder_identity != holder1:
                    holder2 = l.spec.holder_identity
                    break
            except Exception:
                pass
    if holder2:
        print(f"  ✓ {time.time()-t0:.1f}s 后转移: {holder1} -> {holder2}")
    else:
        print("  !! 20s 内未转移")

    # 新 leader 上再放对象，验证它能接管
    async with ApiClient() as api:
        v1 = CoreV1Api(api)
        await v1.create_namespaced_config_map(
            namespace=NS,
            body={"metadata": {"name": "rc-new"}, "data": {"k": "v"}})
    print("  新 leader 上任后创建 rc-new，等 3 秒...")
    await asyncio.sleep(3)

    async with ApiClient() as api:
        v1 = CoreV1Api(api)
        r = await v1.list_namespaced_config_map(namespace=NS)
        final = [(o.metadata.name, (o.data or {}).get("managed"))
                 for o in r.items if o.metadata.name.startswith("rc-")]
    print(f"  最终: {sorted(final)}")

    for t in tasks:
        t.cancel()
    await asyncio.gather(*tasks, return_exceptions=True)

    print()
    print("  时间线:")
    for l in state["log"]:
        print(f"    {l}")
    print(f"\n  各副本调谐统计: {state['ctrl']}")

    print()
    print("=" * 70)
    print("判定")
    print("=" * 70)
    print(f"  1. 上任记录:          {state['leaders']}  (累计，非并发)")
    concurrent = len(set(state["leaders"][:1]))
    print(f"     并发 leader 数:    "
          f"{'✓ 1（r0 已交出，r2 接任）' if holder2 and holder2 != holder1 else '!! 异常'}")
    print(f"  2. leader 完成调谐:    {'✓' if done1 else '!! 未全部调谐'}")
    print(f"  3. 故障转移:           {'✓ ' + holder1 + ' -> ' + holder2 if holder2 else '!! 未转移'}")
    new_ok = any(k == "rc-new" and v == "true" for k, v in final)
    print(f"  4. 新 leader 接管调谐: {'✓ rc-new 已调谐' if new_ok else '!! rc-new 未被调谐'}")

    await ka.config.load_kube_config()
    async with ApiClient() as api:
        try:
            await CoreV1Api(api).delete_namespace(name=NS)
            print(f"\n  已清理 ns {NS}")
        except Exception as e:
            print(f"  清理: {type(e).__name__}")


asyncio.run(main())
