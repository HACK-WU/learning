"""修正取证缺陷（两处）

缺陷 1（严重）：404 正对照"读不存在的 ns 竟然没报错"
   —— 若异常捕获失效，则前面 429 统计里的"零 429"可能是假象（错误被吞）。
   必须查清：不存在的 ns 到底返回什么？

缺陷 2：APF PriorityLevel 的 nominal/assured 取到 None
   —— 很可能属性名不是 nominal_concurrency_shares（下划线 vs 驼峰）
   必须列出真实键名再取值。

铁律：先核验测量方法，再核验被测对象。
"""
import asyncio
import json

from kubernetes_asyncio import client as aclient
from kubernetes_asyncio import config as aconfig


async def d1_404():
    print("=== 缺陷 1：读不存在的 namespace 到底返回什么 ===")
    await aconfig.load_kube_config()
    async with aclient.ApiClient() as ac:
        core = aclient.CoreV1Api(ac)
        r = await core.list_namespaced_pod_with_http_info(
            "no-such-ns-xyz-123", limit=1)
        data, status, headers = r
        print("  HTTP status :", status)
        print("  返回类型    :", type(data).__name__)
        print("  items 数量  :", len(getattr(data, "items", []) or []))
        print("  → 空 ns 名的 list 返回 200 + 空列表，不报错（k8s 语义）")
        print("  → 所以它不是 404 正对照！正对照选错了")

        print()
        print("  改用真正会 404 的操作：read 一个不存在的具体对象")
        try:
            await core.read_namespaced_pod("no-such-pod-xyz", "default")
            print("  read 不存在 pod: 竟然没报错")
        except Exception as e:
            print(f"  read 不存在 pod: {type(e).__name__}, "
                  f"status={getattr(e,'status',None)}")

        print()
        print("  再验：read 不存在的 ConfigMap")
        try:
            await core.read_namespaced_config_map("no-such-cm-xyz", "default")
            print("  竟然没报错")
        except Exception as e:
            print(f"  {type(e).__name__}, status={getattr(e,'status',None)}")


async def d2_apf_keys():
    print()
    print("=== 缺陷 2：APF PriorityLevel 真实键名 ===")
    await aconfig.load_kube_config()
    async with aclient.ApiClient() as ac:
        custom = aclient.CustomObjectsApi(ac)
        plc = await custom.list_cluster_custom_object(
            "flowcontrol.apiserver.k8s.io", "v1", "prioritylevelconfigurations")
        items = plc.get("items", [])
        it = items[0]
        print("  顶层键:", list(it.keys()))
        print("  spec 键:", list(it.get("spec", {}).keys()))
        print()
        print("  完整 dump 第一个 Limited 级别的 limited 段:")
        for x in items:
            spec = x.get("spec", {})
            if spec.get("type") == "Limited":
                print("   name:", x["metadata"]["name"])
                print("   limited:", json.dumps(spec.get("limited", {}), indent=6))
                break
        print()
        print("  全部 PLC 的 limited.limitResponse 汇总:")
        for x in items:
            spec = x.get("spec", {})
            if spec.get("type") == "Limited":
                lim = spec.get("limited", {})
                lr = lim.get("limitResponse", {})
                print(f"    {x['metadata']['name']:22s} "
                      f"assured={lim.get('assuredConcurrencyShares')} "
                      f"limitResponse={json.dumps(lr, ensure_ascii=False)}")


async def d3_which_flowschema():
    print()
    print("=== 我方请求落在哪个 FlowSchema（限流归属）===")
    await aconfig.load_kube_config()
    async with aclient.ApiClient() as ac:
        core = aclient.CoreV1Api(ac)
        r = await core.list_namespaced_pod_with_http_info("default", limit=1)
        _, _, headers = r
        fs_uid = headers.get("X-Kubernetes-Pf-Flowschema-Uid")
        pl_uid = headers.get("X-Kubernetes-Pf-Prioritylevel-Uid")
        print("  FlowSchema UID    :", fs_uid)
        print("  PriorityLevel UID :", pl_uid)

        custom = aclient.CustomObjectsApi(ac)
        fs_list = await custom.list_cluster_custom_object(
            "flowcontrol.apiserver.k8s.io", "v1", "flowschemas")
        for it in fs_list.get("items", []):
            if it["metadata"].get("uid") == fs_uid:
                print("  → 命中 FlowSchema:", it["metadata"]["name"])
                print("     优先级:", it["spec"].get("matchingPrecedence"))
                print("     归属 PL:",
                      it["spec"]["priorityLevelConfiguration"]["name"])
        pl_list = await custom.list_cluster_custom_object(
            "flowcontrol.apiserver.k8s.io", "v1", "prioritylevelconfigurations")
        for it in pl_list.get("items", []):
            if it["metadata"].get("uid") == pl_uid:
                print("  → 命中 PriorityLevel:", it["metadata"]["name"])


async def main():
    await d1_404()
    await d2_apf_keys()
    await d3_which_flowschema()


if __name__ == "__main__":
    asyncio.run(main())
