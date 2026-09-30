"""验证 5：Leaderelection 参数校验 + 三副本真实选主

先测硬约束（构造就抛 ValueError），再测真实选主与故障转移。
所有结论必须实测，不凭源码推断。
"""
import asyncio
import sys
import time

sys.path.insert(0, "/mnt/d/projects/learning/k8s/子教程/Python客户端专项/assets/lesson06-async")

import kubernetes_asyncio as ka
from kubernetes_asyncio.client import (ApiClient, CoordinationV1Api,
                                       V1Lease, V1LeaseSpec, V1ObjectMeta)
from kubernetes_asyncio.client.rest import ApiException
from kubernetes_asyncio.leaderelection.electionconfig import Config
from kubernetes_asyncio.leaderelection.leaderelection import LeaderElection
from kubernetes_asyncio.leaderelection.resourcelock.leaselock import LeaseLock

NS = "py-lesson06-le"


def log(m):
    print(f"  {m}")


async def setup(v1n):
    try:
        await v1n.create_namespace(body={"metadata": {"name": NS}})
        log(f"创建 ns {NS}")
    except Exception as e:
        log(f"ns: {type(e).__name__}")


async def test_param_validation():
    print("=" * 70)
    print("1. Config 参数校验（源码显示 jitter_factor=1.2）")
    print("=" * 70)

    await ka.config.load_kube_config()
    async with ApiClient() as api:
        lock = LeaseLock("demo", NS, "id-1", api)

        cases = [
            ("合法: lease=10 renew=5 retry=2", 10, 5, 2, True),
            ("renew <= retry*1.2 (2*1.2=2.4)", 10, 2, 2, False),
            ("lease <= renew", 5, 5, 2, False),
            ("lease < 1", 0.5, 0.3, 0.1, False),
            ("retry >= 1 边界", 10, 5, 1, True),
        ]
        for label, ld, rd, rp, should_ok in cases:
            try:
                Config(lock, ld, rd, rp, None, None)
                got = True
                err = ""
            except ValueError as e:
                got = False
                err = str(e)[:60]
            mark = "OK " if got == should_ok else "!! "
            print(f"  {mark}{label:<34} 可构造={got}  {err}")
        print()
        print("  -> 最小可用组合需满足: retry>=1 且 renew>retry*1.2 且 lease>renew")
        print("     即 retry=2 时 renew 至少 2.5，lease 至少 3")


async def test_three_replicas():
    print()
    print("=" * 70)
    print("2. 三副本真实选主")
    print("=" * 70)

    await ka.config.load_kube_config()

    # 三个副本共用一个 ns，各自独立 ApiClient
    leaders = {}
    events = []

    async def replica(name):
        async with ApiClient() as api:
            coord = CoordinationV1Api(api)
            # 预创建 Lease
            try:
                await coord.create_namespaced_lease(
                    namespace=NS,
                    body=V1Lease(
                        metadata=V1ObjectMeta(name="demo", namespace=NS),
                        spec=V1LeaseSpec(
                            lease_duration_seconds=10,
                            renew_time=None)))
            except ApiException as e:
                if e.status != 409:
                    log(f"  [{name}] 建 Lease: {e.status}")

            lock = LeaseLock("demo", NS, name, api)

            async def on_started():
                leaders[name] = time.time()
                events.append(f"{name} -> 成为 leader")

            async def on_stopped():
                events.append(f"{name} -> 失去 leader")

            cfg = Config(lock, lease_duration=10, renew_deadline=5,
                         retry_period=2,
                         onstarted_leading=on_started,
                         onstopped_leading=on_stopped)
            le = LeaderElection(cfg)
            try:
                await le.run()
            except asyncio.CancelledError:
                pass
            except Exception as e:
                events.append(f"{name} 异常 {type(e).__name__}: {e}")

    tasks = [asyncio.create_task(replica(f"r{i}")) for i in range(3)]
    await asyncio.sleep(6)

    # 看 Lease 里的 holderIdentity
    async with ApiClient() as api:
        coord = CoordinationV1Api(api)
        try:
            lease = await coord.read_namespaced_lease(name="demo", namespace=NS)
            holder = lease.spec.holder_identity
            log(f"\n  Lease holderIdentity = {holder}")
        except Exception as e:
            holder = None
            log(f"  读 Lease: {type(e).__name__}")

    log(f"  各副本回调记录: {leaders}")
    log(f"  事件: {events}")

    print()
    print("  判定:")
    active = [n for n in leaders]
    if len(active) == 1:
        print(f"    ✓ 恰好一个 leader: {active[0]}")
    else:
        print(f"    !! leader 数量异常: {len(active)} -> {active}")

    # 杀掉 leader，看是否转移
    if holder:
        print()
        print("=" * 70)
        print(f"3. 故障转移：cancel 掉当前 leader（{holder}）")
        print("=" * 70)
        idx = int(holder[1])
        tasks[idx].cancel()
        try:
            await tasks[idx]
        except asyncio.CancelledError:
            pass
        log(f"  已 cancel {holder}，等待 15 秒（lease=10s）...")

        t0 = time.time()
        new_holder = None
        async with ApiClient() as api:
            coord = CoordinationV1Api(api)
            for _ in range(40):
                await asyncio.sleep(0.5)
                try:
                    l = await coord.read_namespaced_lease(name="demo", namespace=NS)
                    if l.spec.holder_identity and l.spec.holder_identity != holder:
                        new_holder = l.spec.holder_identity
                        break
                except Exception:
                    pass
        if new_holder:
            print(f"    ✓ {time.time()-t0:.1f}s 后转移到 {new_holder}")
        else:
            print(f"    !! 20 秒内未发生转移")

        for t in tasks:
            t.cancel()
        await asyncio.gather(*tasks, return_exceptions=True)


async def main():
    await ka.config.load_kube_config()
    async with ApiClient() as api:
        from kubernetes_asyncio.client import CoreV1Api
        await setup(CoreV1Api(api))

    await test_param_validation()
    await test_three_replicas()

    print()
    await ka.config.load_kube_config()
    async with ApiClient() as api:
        from kubernetes_asyncio.client import CoreV1Api
        try:
            await CoreV1Api(api).delete_namespace(name=NS)
            print(f"  已清理 ns {NS}")
        except Exception as e:
            print(f"  清理: {type(e).__name__}")


asyncio.run(main())
