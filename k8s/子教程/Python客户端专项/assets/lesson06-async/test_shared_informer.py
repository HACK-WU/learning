"""验证 8：SharedInformer 实测

考三个问题（都必须实测，不凭推断）：
  Q1 成本：共享后 watch 连接数是否**与消费者数无关**？
  Q2 正确性：多个消费者是否都收到完整事件？一个挂了会不会拖垮别人？
  Q3 语义澄清：能否"一条连接 watch 多种资源"？（预期：不能，协议限制）
"""
import asyncio
import re
import subprocess
import sys
import time

sys.path.insert(0, "/mnt/d/projects/learning/k8s/子教程/Python客户端专项/assets/lesson06-async")

import kubernetes_asyncio as ka
from kubernetes_asyncio.client import ApiClient, CoreV1Api

from shared_informer import (NaiveMultiInformer, ResourceKind,
                             SharedController, SharedInformer)

NS = "py-lesson06-shared2"


def apiport():
    r = subprocess.run(
        ["bash", "-c",
         "kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}'"],
        capture_output=True, text=True)
    m = re.search(r":(\d+)\s*$", (r.stdout or "").strip())
    return m.group(1) if m else "6443"


PORT = apiport()


def conns():
    r = subprocess.run(
        ["bash", "-c",
         f"ss -tn state established '( dport = :{PORT} )' | tail -n +2 | wc -l"],
        capture_output=True, text=True)
    try:
        return int((r.stdout or "0").strip().splitlines()[0])
    except Exception:
        return -1


async def setup(v1):
    try:
        await v1.create_namespace(body={"metadata": {"name": NS}})
    except Exception:
        try:
            r = await v1.list_namespaced_config_map(namespace=NS)
            for o in r.items:
                if o.metadata.name.startswith("sh-"):
                    await v1.delete_namespaced_config_map(
                        name=o.metadata.name, namespace=NS)
        except Exception:
            pass
    await asyncio.sleep(0.4)


def kinds(v1):
    return [
        ResourceKind("configmaps", v1.list_namespaced_config_map),
        ResourceKind("secrets", v1.list_namespaced_secret),
    ]


async def q1_cost():
    print("=" * 70)
    print("Q1 成本：watch 连接数 vs 消费者数")
    print("=" * 70)
    print(f"  apiserver 端口 {PORT}，资源种类固定 2（configmaps + secrets）\n")

    await ka.config.load_kube_config()
    async with ApiClient() as api:
        v1 = CoreV1Api(api)
        await setup(v1)
        await asyncio.sleep(0.5)
        base = conns()

        print(f"  基线连接数 = {base}")
        print()
        print(f"  {'消费者数':<8} {'朴素(连接)':<12} {'共享(连接)':<12} 判定")

        for n in (1, 2, 3):
            # --- 朴素：n 个消费者 × 2 资源 ---
            naive = NaiveMultiInformer(NS, api)
            async def noop(et, o):
                pass
            for c in range(n):
                naive.add_consumer(c, "configmaps",
                                   v1.list_namespaced_config_map, noop)
                naive.add_consumer(c, "secrets",
                                   v1.list_namespaced_secret, noop)
            t = asyncio.create_task(naive.run())
            await asyncio.sleep(3.0)
            n_conn = conns() - base
            naive.stop.set()
            await naive.shutdown()
            t.cancel()
            try:
                await t
            except asyncio.CancelledError:
                pass
            await asyncio.sleep(1.0)

            # --- 共享：2 资源，n 个订阅者 ---
            si = SharedInformer(NS, kinds(v1))
            for c in range(n):
                si.subscribe("configmaps", noop)
                si.subscribe("secrets", noop)
            await si.start()
            await asyncio.sleep(3.0)
            s_conn = conns() - base
            await si.shutdown()
            await asyncio.sleep(1.0)

            ok = "✓ 共享不随消费者增长" if s_conn <= 2 else "!! 异常"
            print(f"  {n:<10} {n_conn:<14} {s_conn:<14} {ok}")
            print(f"            (watch_count: 朴素={n*2} 共享={2})")

    print()
    print("  结论: 朴素 = 消费者数×资源数；共享 = 资源数（与消费者数无关）")


async def q2_correctness():
    print()
    print("=" * 70)
    print("Q2 正确性：多消费者事件完整性 + 故障隔离")
    print("=" * 70)

    await ka.config.load_kube_config()
    async with ApiClient() as api:
        v1 = CoreV1Api(api)
        await setup(v1)

        got_a, got_b, got_bad = [], [], []

        async def consumer_a(et, o):
            got_a.append((et, o.metadata.name))

        async def consumer_b(et, o):
            got_b.append((et, o.metadata.name))

        async def consumer_bad(et, o):
            got_bad.append(o.metadata.name)
            raise RuntimeError("故意炸的订阅者")

        si = SharedInformer(NS, kinds(v1))
        si.subscribe("configmaps", consumer_a)
        si.subscribe("configmaps", consumer_b)
        si.subscribe("configmaps", consumer_bad)   # 每事件都抛异常
        await si.start()
        await asyncio.sleep(1.5)

        for i in range(3):
            await v1.create_namespaced_config_map(
                namespace=NS,
                body={"metadata": {"name": f"sh-{i}"}, "data": {"k": "v"}})
        await asyncio.sleep(3.0)
        alive = not si.stop.is_set() and si.fatal is None
        await si.shutdown()

        na = len([x for x in got_a if x[1].startswith("sh-")])
        nb = len([x for x in got_b if x[1].startswith("sh-")])
        nbad = len(got_bad)
        err = si.kinds["configmaps"].stats["handler_error"]

        print(f"\n  创建 3 个 ConfigMap")
        print(f"    消费者A 收到: {na}")
        print(f"    消费者B 收到: {nb}")
        print(f"    坏订阅者被调用: {nbad} 次，记 handler_error={err}")
        print(f"    informer 存活: {alive}   fatal={si.fatal}")
        print()
        print(f"  判定:")
        print(f"    1. 两消费者都完整: {'✓' if na >= 3 and nb >= 3 else '!! 丢失'}")
        print(f"    2. 坏订阅者未拖垮: {'✓ 隔离成功' if alive and err >= 3 else '!! 未隔离'}")


async def q3_semantics():
    print()
    print("=" * 70)
    print("Q3 语义：能否一条连接 watch 多种资源？")
    print("=" * 70)
    await ka.config.load_kube_config()
    async with ApiClient() as api:
        v1 = CoreV1Api(api)
        # 试着用 raw 请求 watch 一个"多种资源"的 path
        from kubernetes_asyncio.client.rest import ApiException
        try:
            r = await api.call_api(
                "GET",
                f"/api/v1/watch/namespaces/{NS}",
                auth_settings=["BearerToken"], response_type="object",
                _request_timeout=3)
            print(f"  居然成功了: {type(r)}")
        except ApiException as e:
            print(f"  /api/v1/watch/namespaces/{{ns}} -> HTTP {e.status}")
        except Exception as e:
            print(f"  {type(e).__name__}: {str(e)[:120]}")

        # 对比：单资源 path 是正常的
        try:
            r = await v1.list_namespaced_config_map(namespace=NS,
                                                    _request_timeout=3)
            print(f"  单资源 list 正常: {len(r.items)} 个对象")
        except Exception as e:
            print(f"  list: {type(e).__name__}")

    print()
    print("  结论: watch 的 path 必须指定具体资源 "
          "(/api/v1/namespaces/{ns}/configmaps?watch=true)")
    print("        协议上**不存在**『一次 watch 多种资源』。")
    print("        SharedInformer 的 'shared' = 多消费者共享，不是一连接多资源。")


async def q4_controller():
    print()
    print("=" * 70)
    print("Q4 端到端：SharedController 调谐 + 审计")
    print("=" * 70)

    await ka.config.load_kube_config()
    async with ApiClient() as api:
        v1 = CoreV1Api(api)
        await setup(v1)

        ctrl = SharedController(api, NS, kinds(v1))
        t = asyncio.create_task(ctrl.run(duration=9, workers=3))
        await asyncio.sleep(2.0)

        for i in range(4):
            await v1.create_namespaced_config_map(
                namespace=NS,
                body={"metadata": {"name": f"sh-c{i}"}, "data": {"k": "v"}})
        await asyncio.sleep(5.0)
        await ctrl.shutdown()
        try:
            await t
        except asyncio.CancelledError:
            pass

        r = await v1.list_namespaced_config_map(namespace=NS)
        managed = [(o.metadata.name, (o.data or {}).get("managed"))
                   for o in r.items if o.metadata.name.startswith("sh-c")]
        print(f"\n  调谐结果: {sorted(managed)}")
        print(f"  stats: {dict(ctrl.stats)}")
        print(f"  audit: {dict(ctrl.audit)}")
        print(f"  watch 连接数: {ctrl.informer.watch_count} (资源种类数)")
        ok = all(v == "true" for _, v in managed) and len(managed) == 4
        print(f"\n  判定: {'✓ 4/4 调谐完成，审计独立计数' if ok else '!! 未全部调谐'}")


async def main():
    await q1_cost()
    await q2_correctness()
    await q3_semantics()
    await q4_controller()

    await ka.config.load_kube_config()
    async with ApiClient() as api:
        try:
            await CoreV1Api(api).delete_namespace(name=NS)
            print(f"\n已清理 ns {NS}")
        except Exception as e:
            print(f"清理: {type(e).__name__}")


asyncio.run(main())
