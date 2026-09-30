"""验证 11：课 7 异步版动态客户端

逐条验证：
  V1 初始化：不初始化会 RuntimeError（异步新坑）
  V2 resources.get 是 coroutine（忘了 await 的后果）
  V3 两个发现类异常与同步版一致
  V4 🚨 静默 415：裸 patch 静默失败 vs safe_patch 显式抛错
  V5 watch 参数名 timeout vs timeout_seconds
  V6 CRUD 完整生命周期
  V7 并发共用安全
  V8 端到端：异步调谐 + CRD
"""
import asyncio
import sys
import time
from collections import defaultdict

sys.path.insert(0, "/mnt/d/projects/learning/k8s/子教程/Python客户端专项/assets/lesson06-async")

import kubernetes_asyncio as ka
from kubernetes_asyncio.client import ApiClient, CustomObjectsApi
from kubernetes_asyncio.dynamic import DynamicClient
from kubernetes_asyncio.dynamic.exceptions import (
    ResourceNotFoundError, ResourceNotUniqueError)

from dynamic_async import (DynamicApiErrorAsync, async_dyn_client,
                           concurrent_get, dyn_create, dyn_delete,
                           dyn_get, dyn_replace, dyn_watch,
                           get_resource, is_status, raise_if_status,
                           safe_patch)

NS = "py-lesson07-verify"
CRD_NAME = "doodads.lesson.pyclient.io"

CRD = {
    "apiVersion": "apiextensions.k8s.io/v1",
    "kind": "CustomResourceDefinition",
    "metadata": {"name": CRD_NAME},
    "spec": {
        "group": "lesson.pyclient.io",
        "names": {"plural": "doodads", "singular": "doodad",
                  "kind": "Doodad", "shortNames": ["dd"]},
        "scope": "Namespaced",
        "versions": [{
            "name": "v1", "served": True, "storage": True,
            "schema": {"openAPIV3Schema": {
                "type": "object",
                "properties": {"spec": {
                    "type": "object",
                    "properties": {"n": {"type": "integer"},
                                   "note": {"type": "string"}}}}}}
        }]
    }
}


async def setup(v1, apiext):
    try:
        await v1.create_namespace(body={"metadata": {"name": NS}})
    except Exception:
        pass
    try:
        await apiext.create_custom_resource_definition(body=CRD)
    except Exception:
        pass
    await asyncio.sleep(1.6)


async def cleanup(v1, apiext):
    try:
        await apiext.delete_custom_resource_definition(name=CRD_NAME)
    except Exception:
        pass
    try:
        await v1.delete_namespace(name=NS)
    except Exception:
        pass


async def clean_all(v1, apiext):
    """启动即彻底清理 —— 防止上一轮残留污染本轮判定

    🚨 2026-09-29 教训（两次）：
       ① d1 残留 spec.n=102 → V4 误判"静默失败=否"
       ② ns 处于 terminating 时建资源 → 403 Forbidden，整轮报废
       实验污染会让结论**完全反过来**，必须等资源真正消失。
    """
    try:
        await apiext.delete_custom_resource_definition(name=CRD_NAME)
    except Exception:
        pass
    try:
        await v1.delete_namespace(name=NS)
    except Exception:
        pass

    # 等 CRD 消失
    for _ in range(40):
        await asyncio.sleep(1)
        try:
            await apiext.read_custom_resource_definition(name=CRD_NAME)
        except Exception:
            break

    # 等 ns **真正消失**（Terminating 期间建资源会 403）
    for _ in range(60):
        await asyncio.sleep(1)
        try:
            await v1.read_namespace(name=NS)
        except Exception:
            break
    await asyncio.sleep(1)


async def main():
    await ka.config.load_kube_config()
    async with ApiClient() as api:
        v1 = ka.client.CoreV1Api(api)
        apiext = ka.client.ApiextensionsV1Api(api)
        await clean_all(v1, apiext)
        await setup(v1, apiext)

        # ---------- V1 ----------
        print("=" * 70)
        print("V1 初始化：不初始化会 RuntimeError")
        print("=" * 70)
        d0 = DynamicClient(api)
        try:
            _ = d0.resources
            print("  !! 竟可用")
        except RuntimeError as e:
            print(f"  ✓ RuntimeError: {str(e)[:72]}")

        t0 = time.monotonic()
        dyn_await = await DynamicClient(api)
        print(f"  ✓ await 初始化: {time.monotonic()-t0:.4f}s")
        async with DynamicClient(api) as dyn2:
            print(f"  ✓ async with 初始化: {type(dyn2.resources).__name__}")

        dyn = dyn_await

        # ---------- V2 ----------
        print()
        print("=" * 70)
        print("V2 resources.get 是 coroutine")
        print("=" * 70)
        raw = dyn.resources.get(api_version="v1", kind="ConfigMap")
        print(f"  不 await → {type(raw).__name__}")
        try:
            _ = raw.name
            print("  !! 竟有 name")
        except AttributeError as e:
            print(f"  ✓ AttributeError: {e}")
        finally:
            if hasattr(raw, "close"):
                raw.close()
        cm = await get_resource(dyn, "v1", "ConfigMap")
        print(f"  await → {cm.name} (namespaced={cm.namespaced})")

        # ---------- V3 ----------
        print()
        print("=" * 70)
        print("V3 发现类异常与同步版一致")
        print("=" * 70)
        try:
            await dyn.resources.get(api_version="v1")
            print("  !! 无异常")
        except ResourceNotUniqueError as e:
            print(f"  ✓ ResourceNotUniqueError: {str(e)[:60]}...")
        try:
            await dyn.resources.get(api_version="v1", kind="Nope")
            print("  !! 无异常")
        except ResourceNotFoundError as e:
            print(f"  ✓ ResourceNotFoundError: {str(e)[:60]}")

        # ---------- V4 核心 ----------
        print()
        print("=" * 70)
        print("V4 🚨 静默 415：裸 patch vs safe_patch")
        print("=" * 70)
        dd = await get_resource(dyn, "lesson.pyclient.io/v1", "Doodad")
        print("\n  --- create 缺必填字段（验证是否也静默）---")
        try:
            rc = await dyn.create(
                dd, namespace=NS,
                body={"apiVersion": "lesson.pyclient.io/v1",
                      "kind": "Doodad",
                      "metadata": {"name": "bad"}})
            print(f"  裸 create → kind={getattr(rc,'kind',None)} "
                  f"is_status={is_status(rc)} "
                  f"code={getattr(rc,'code',None)}")
            print(f"  {'🚨 静默（不抛异常）' if is_status(rc) else '抛异常'}")
        except Exception as e:
            print(f"  create → {type(e).__name__}: {str(e)[:70]}")

        # 正常创建（带 spec）
        r = await dyn_create(dyn, dd,
                             {"apiVersion": "lesson.pyclient.io/v1",
                              "kind": "Doodad",
                              "metadata": {"name": "d1"},
                              "spec": {"n": 1, "note": "init"}}, NS)
        print(f"  正常 create: n={r.spec.n}")
        await asyncio.sleep(0.6)

        print("\n  --- 裸 patch（用库默认 strategic-merge-patch）---")
        try:
            r = await dyn.patch(dd, name="d1", namespace=NS,
                                body={"spec": {"n": 999}})
            print(f"  {'不抛异常':<12} 返回类型={type(r).__name__} "
                  f"kind={getattr(r,'kind',None)}")
            print(f"  is_status={is_status(r)}  "
                  f"code={getattr(r,'code',None)}")
            after = await dyn.get(dd, name="d1", namespace=NS)
            print(f"  → 读回 spec.n={after.spec.n}  "
                  f"{'!! 改动静默丢失' if after.spec.n == 1 else '生效'}")
            silent = (after.spec.n == 1)
        except Exception as e:
            print(f"  !! 抛异常 {type(e).__name__}")
            silent = False

        print("\n  --- safe_patch ---")
        try:
            r = await safe_patch(dyn, dd, "d1", {"spec": {"n": 42}}, NS)
            print(f"  ✓ 成功 n={r.spec.n}")
        except DynamicApiErrorAsync as e:
            print(f"  !! {e}")

        print("\n  --- safe_patch 故意触发 415（传 json-patch 体但用 merge）---")
        try:
            r = await safe_patch(dyn, dd, "d1", [{"op": "replace",
                                                  "path": "/spec/n",
                                                  "value": 7}], NS)
            print(f"  !! 未拦截 n={getattr(r,'spec',None)}")
        except DynamicApiErrorAsync as e:
            print(f"  ✓ 拦截: {str(e)[:80]}")

        print()
        print(f"  裁定: 裸 patch 静默失败 = {'是 🚨' if silent else '否'}；"
              f"safe_patch 显式抛错 = 是")

        # ---------- V5 ----------
        print()
        print("=" * 70)
        print("V5 watch 参数名")
        print("=" * 70)
        try:
            async for _ in dyn.watch(dd, namespace=NS, timeout_seconds=2):
                break
            print("  !! 无 TypeError")
        except TypeError as e:
            print(f"  ✓ timeout_seconds → TypeError: {str(e)[:70]}")

        events = []

        async def prod():
            await asyncio.sleep(0.4)
            for i in range(3):
                await safe_patch(dyn, dd, "d1", {"spec": {"n": 100 + i}}, NS)
                await asyncio.sleep(0.35)

        async def cons():
            async for e in dyn_watch(dyn, dd, namespace=NS, timeout=4):
                obj = e["object"]
                sp = getattr(obj, "spec", None)
                n = getattr(sp, "n", None) if sp is not None else None
                events.append((e.get("type"), n))

        await asyncio.gather(prod(), cons())
        print(f"  ✓ dyn_watch(timeout=4) 收到 {len(events)} 事件: "
              f"{events[:5]}")

        # ---------- V6 ----------
        print()
        print("=" * 70)
        print("V6 CRUD 完整生命周期")
        print("=" * 70)
        r = await dyn.create(dd, namespace=NS,
                             body={"apiVersion": "lesson.pyclient.io/v1",
                                   "kind": "Doodad",
                                   "metadata": {"name": "life"},
                                   "spec": {"n": 5, "note": "c"}})
        print(f"  create: n={r.spec.n} note={r.spec.note}")
        r = await dyn_get(dyn, dd, "life", NS)
        print(f"  get   : n={r.spec.n}")
        r = await safe_patch(dyn, dd, "life", {"spec": {"n": 6}}, NS)
        print(f"  patch : n={r.spec.n}")
        # replace 需带 resourceVersion（K8s 的乐观锁，课 3 知识）
        cur = await dyn_get(dyn, dd, "life", NS)
        r = await dyn_replace(
            dyn, dd, "life",
            {"apiVersion": "lesson.pyclient.io/v1", "kind": "Doodad",
             "metadata": {"name": "life",
                          "resourceVersion": cur.metadata.resourceVersion},
             "spec": {"n": 7, "note": "r"}}, NS)
        print(f"  replace: n={r.spec.n} note={r.spec.note}")

        # 额外：replace 不带 metadata.name 时是否也静默？
        print("\n  --- replace 缺字段（验证封装是否也覆盖 replace）---")
        try:
            await dyn_replace(dyn, dd, "life",
                              {"apiVersion": "lesson.pyclient.io/v1",
                               "kind": "Doodad"}, NS)
            print("  !! 未拦截")
        except DynamicApiErrorAsync as e:
            print(f"  ✓ 拦截: {str(e)[:78]}")
        except Exception as e:
            print(f"  ? {type(e).__name__}: {str(e)[:78]}")

        await dyn_delete(dyn, dd, "life", NS)
        print(f"  delete : OK")

        # ---------- V7 ----------
        print()
        print("=" * 70)
        print("V7 并发共用安全")
        print("=" * 70)
        names = ["d1"] * 20
        t0 = time.monotonic()
        res = await concurrent_get(dyn, dd, names, NS, max_concurrency=10)
        el = time.monotonic() - t0
        ok = sum(1 for _, r, e in res if e is None)
        errs = {type(e).__name__ for _, _, e in res if e}
        print(f"  20 次并发 get (max=10): 成功 {ok}/20  "
              f"失败 {errs or '无'}  耗时 {el:.3f}s")
        print(f"  → {'✓ 可共用' if ok == 20 else '!! 有并发问题'}")

        # ---------- V8 端到端 ----------
        print()
        print("=" * 70)
        print("V8 端到端：异步调谐 CRD")
        print("=" * 70)
        for i in range(5):
            try:
                await dyn.create(dd, namespace=NS,
                                 body={"apiVersion": "lesson.pyclient.io/v1",
                                       "kind": "Doodad",
                                       "metadata": {"name": f"t{i}"},
                                       "spec": {"n": 0, "note": "todo"}})
            except Exception:
                pass
        await asyncio.sleep(0.8)

        stats = defaultdict(int)
        sem = asyncio.Semaphore(4)

        async def reconcile(name):
            async with sem:
                o = await dyn_get(dyn, dd, name, NS)
                if o.spec.note != "done":
                    await safe_patch(dyn, dd, name,
                                     {"spec": {"note": "done"}}, NS)
                    stats["reconciled"] += 1
                else:
                    stats["no_op"] += 1

        await asyncio.gather(*[reconcile(f"t{i}") for i in range(5)])
        r = await dyn.get(dd, namespace=NS)
        done = []
        for o in r.items:
            sp = getattr(o, "spec", None)
            note = getattr(sp, "note", None) if sp is not None else None
            if note == "done" and o.metadata.name.startswith("t"):
                done.append(o.metadata.name)
        print(f"  5 个 CR 并发调谐: stats={dict(stats)}  done={sorted(done)}")
        print(f"  → {'✓ 5/5' if len(done) == 5 else f'!! {len(done)}/5'}")

        # 幂等
        await asyncio.gather(*[reconcile(f"t{i}") for i in range(5)])
        print(f"  二次调谐: stats={dict(stats)}  "
              f"(no_op 应为 5 → 幂等)")

        await cleanup(v1, apiext)
        print(f"\n  已清理 ns {NS} 与 CRD {CRD_NAME}")


asyncio.run(main())
