"""SSA 验证（补充课 7 异步版讲义的未实测项）

验证：
  V-A 异步版确实有 server_side_apply（纠正上轮"未暴露"的误判）
  V-B safe_apply 能把静默 Status 变显式异常
  V-C 幂等性
  V-D 冲突与 force_conflicts
  V-E 字段归属语义（跨 manager 保留 / 同 manager 删除）
"""
import asyncio
import inspect
import sys

sys.path.insert(0, "/mnt/d/projects/learning/k8s/子教程/Python客户端专项/assets/lesson06-async")

import kubernetes_asyncio as ka
from kubernetes_asyncio.client import ApiClient
from kubernetes_asyncio.dynamic import DynamicClient

from dynamic_async import (DynamicApiErrorAsync, is_status, safe_apply,
                           safe_patch)

NS = "py-lesson07-ssav"
CRD_NAME = "gizmos.lesson.pyclient.io"
AV = "lesson.pyclient.io/v1"
KIND = "Gizmo"

CRD = {
    "apiVersion": "apiextensions.k8s.io/v1",
    "kind": "CustomResourceDefinition",
    "metadata": {"name": CRD_NAME},
    "spec": {
        "group": "lesson.pyclient.io",
        "names": {"plural": "gizmos", "singular": "gizmo",
                  "kind": KIND},
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


def sp(r):
    s = getattr(r, "spec", None)
    return (getattr(s, "n", None), getattr(s, "note", None))


async def main():
    await ka.config.load_kube_config()
    async with ApiClient() as api:
        v1 = ka.client.CoreV1Api(api)
        apiext = ka.client.ApiextensionsV1Api(api)

        # 彻底清理（防实验污染）
        try:
            await apiext.delete_custom_resource_definition(name=CRD_NAME)
        except Exception:
            pass
        try:
            await v1.delete_namespace(name=NS)
        except Exception:
            pass
        for _ in range(40):
            await asyncio.sleep(1)
            try:
                await apiext.read_custom_resource_definition(name=CRD_NAME)
            except Exception:
                break
        for _ in range(60):
            await asyncio.sleep(1)
            try:
                await v1.read_namespace(name=NS)
            except Exception:
                break

        try:
            await v1.create_namespace(body={"metadata": {"name": NS}})
        except Exception:
            pass
        try:
            await apiext.create_custom_resource_definition(body=CRD)
        except Exception:
            pass
        await asyncio.sleep(1.6)

        dyn = await DynamicClient(api)

        # ---------- V-A ----------
        print("=" * 70)
        print("V-A 异步版是否有 server_side_apply")
        print("=" * 70)
        methods = sorted(n for n in dir(DynamicClient)
                         if not n.startswith("_"))
        print(f"  方法清单: {methods}")
        print(f"  ✓ 含 server_side_apply: "
              f"{'server_side_apply' in methods}")
        print(f"  签名: {inspect.signature(DynamicClient.server_side_apply)}")
        print("  → 纠正：上轮判'未暴露'是我只查了预设 7 个方法名，"
              "没列全量 dir()，属测法错误")

        wg = await dyn.resources.get(api_version=AV, kind=KIND)

        # ---------- V-B ----------
        print()
        print("=" * 70)
        print("V-B safe_apply 把静默 Status 变显式异常")
        print("=" * 70)
        print("\n  --- 裸 SSA 缺 apiVersion/kind ---")
        try:
            r = await dyn.server_side_apply(wg, body={"spec": {"n": 1}},
                                            name="x1", namespace=NS,
                                            field_manager="m")
            print(f"  裸 → is_status={is_status(r)} "
                  f"code={getattr(r,'code',None)}  "
                  f"{'🚨 静默' if is_status(r) else ''}")
        except Exception as e:
            print(f"  ✓ 抛异常 {type(e).__name__}: {str(e)[:80]}")

        print("\n  --- safe_apply 同场景 ---")
        try:
            await safe_apply(dyn, wg, {"spec": {"n": 1}}, name="x1",
                             namespace=NS, field_manager="m")
            print("  !! 未拦截")
        except DynamicApiErrorAsync as e:
            print(f"  ✓ 拦截: {str(e)[:80]}")

        print("\n  --- 缺 field_manager（422）---")
        try:
            r = await dyn.server_side_apply(
                wg, body={"apiVersion": AV, "kind": KIND,
                          "metadata": {"name": "x2"},
                          "spec": {"n": 1}}, name="x2", namespace=NS)
            print(f"  裸 → is_status={is_status(r)} code={getattr(r,'code',None)}")
        except Exception as e:
            print(f"  {type(e).__name__}: {str(e)[:80]}")

        # 正常 apply
        r = await safe_apply(
            dyn, wg,
            {"apiVersion": AV, "kind": KIND,
             "metadata": {"name": "g1"}, "spec": {"n": 1, "note": "init"}},
            name="g1", namespace=NS, field_manager="mgr-v")
        print(f"\n  正常 safe_apply: {sp(r)}")
        print(f"  managedFields: "
              f"{[(m.manager, m.operation) for m in r.metadata.managedFields]}")

        # ---------- V-C ----------
        print()
        print("=" * 70)
        print("V-C 幂等")
        print("=" * 70)
        same = {"apiVersion": AV, "kind": KIND,
                "metadata": {"name": "g1"},
                "spec": {"n": 5, "note": "idem"}}
        r1 = await safe_apply(dyn, wg, same, name="g1", namespace=NS,
                              field_manager="mgr-v")
        r2 = await safe_apply(dyn, wg, same, name="g1", namespace=NS,
                              field_manager="mgr-v")
        print(f"  第一次 rv={r1.metadata.resourceVersion}")
        print(f"  第二次 rv={r2.metadata.resourceVersion}")
        print(f"  → {'✓ 幂等' if r1.metadata.resourceVersion == r2.metadata.resourceVersion else '!! 非幂等'}")

        # ---------- V-D ----------
        print()
        print("=" * 70)
        print("V-D 冲突与 force_conflicts")
        print("=" * 70)
        await safe_patch(dyn, wg, "g1", {"spec": {"n": 50}}, NS)
        await asyncio.sleep(0.4)
        print("  先用 merge-patch 改 n=50（manager=OpenAPI-Generator）")
        try:
            await safe_apply(dyn, wg,
                             {"apiVersion": AV, "kind": KIND,
                              "metadata": {"name": "g1"},
                              "spec": {"n": 60}}, name="g1", namespace=NS,
                             field_manager="mgr-v")
            print("  !! 未冲突")
        except DynamicApiErrorAsync as e:
            print(f"  ✓ 拦截冲突: {str(e)[:100]}")
        r = await safe_apply(dyn, wg,
                             {"apiVersion": AV, "kind": KIND,
                              "metadata": {"name": "g1"},
                              "spec": {"n": 70}}, name="g1", namespace=NS,
                             field_manager="mgr-v", force_conflicts=True)
        print(f"  force_conflicts=True → {sp(r)}  "
              f"managers={[m.manager for m in r.metadata.managedFields]}")

        # ---------- V-E ----------
        print()
        print("=" * 70)
        print("V-E 字段归属语义")
        print("=" * 70)
        await safe_apply(dyn, wg,
                         {"apiVersion": AV, "kind": KIND,
                          "metadata": {"name": "e1"}, "spec": {"n": 11}},
                         name="e1", namespace=NS, field_manager="mgr-a")
        await asyncio.sleep(0.3)
        await safe_apply(dyn, wg,
                         {"apiVersion": AV, "kind": KIND,
                          "metadata": {"name": "e1"},
                          "spec": {"note": "from-b"}},
                         name="e1", namespace=NS, field_manager="mgr-b")
        await asyncio.sleep(0.3)
        r = await safe_apply(dyn, wg,
                             {"apiVersion": AV, "kind": KIND,
                              "metadata": {"name": "e1"},
                              "spec": {"n": 12}},
                             name="e1", namespace=NS, field_manager="mgr-a")
        keep = (sp(r)[1] == "from-b")
        print(f"  E1 跨 manager：A 只交 n → {sp(r)}  "
              f"note {'保留 ✓' if keep else '被清 ✗'}")

        await safe_apply(dyn, wg,
                         {"apiVersion": AV, "kind": KIND,
                          "metadata": {"name": "e2"},
                          "spec": {"n": 21, "note": "both"}},
                         name="e2", namespace=NS, field_manager="mgr-c")
        await asyncio.sleep(0.3)
        r = await safe_apply(dyn, wg,
                             {"apiVersion": AV, "kind": KIND,
                              "metadata": {"name": "e2"},
                              "spec": {"note": "only"}},
                             name="e2", namespace=NS, field_manager="mgr-c")
        drop = (sp(r)[0] is None)
        print(f"  E2 同 manager：先 n+note 再只交 note → {sp(r)}  "
              f"n {'被清 ✓' if drop else '保留 ✗'}")
        print(f"\n  → SSA 语义与标准{'一致 ✓' if keep and drop else '存在差异 ✗'}")

        try:
            await apiext.delete_custom_resource_definition(name=CRD_NAME)
        except Exception:
            pass
        try:
            await v1.delete_namespace(name=NS)
            print(f"\n  已清理 {NS} / {CRD_NAME}")
        except Exception:
            pass


asyncio.run(main())
