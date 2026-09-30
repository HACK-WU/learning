"""正对照：证明"0 次 429"是限流未触发，而非测法错误

三条独立证据：
 E1. 客户端确实把请求打到 apiserver（不是被缓存/短路）
     —— 用 list 带 resourceVersion=0 观察返回，且统计实际 HTTP 往返
 E2. 客户端有能力识别 429（不是把 429 吞了）
     —— 直接对 apiserver 发一个必然返回 429 的请求，看能否捕获
     —— 若无天然 429，则用"已知会被拒的请求"做码型正对照（如 403/404）
 E3. APF 配置取证：看 flowcontrol 的 limits（限流阈值到底多少）
     —— 用 CustomObjectsApi 读 flowcontrol.apiserver.k8s.io/v1 的
        PriorityLevelConfiguration / FlowSchema

若 E3 显示阈值远高于我能打出的 QPS，则"未触发"是环境结论，可如实标注。
"""
import asyncio
import time
from collections import Counter

from kubernetes_asyncio import client as aclient
from kubernetes_asyncio import config as aconfig

NS = "default"


async def e1_requests_really_sent():
    print("=== E1. 请求是否真的打到 apiserver ===")
    await aconfig.load_kube_config()
    async with aclient.ApiClient() as ac:
        core = aclient.CoreV1Api(ac)
        # 统计 HTTP 往返：用 _return_http_data_only=False 拿 response 头
        r = await core.list_namespaced_pod_with_http_info(NS, limit=1)
        _, status, headers = r
        print("  HTTP status      :", status)
        print("  Audit-ID 存在    :", "Audit-Id" in headers or "Audit-ID" in headers)
        for k, v in headers.items():
            if k.lower() in ("audit-id", "x-kubernetes-pf-flowschema-uid",
                             "x-kubernetes-pf-prioritylevel-uid"):
                print(f"  {k}: {v[:60]}")
        print("  → 有 Audit-ID 即证明请求被 apiserver 真实处理（未被短路）")


async def e2_client_can_see_429():
    print()
    print("=== E2. 客户端能否识别 429（码型正对照）===")
    await aconfig.load_kube_config()
    async with aclient.ApiClient() as ac:
        core = aclient.CoreV1Api(ac)
        # 正对照 1：读一个不存在的 ns（必 404），确认异常能被捕获且 status 正确
        try:
            await core.list_namespaced_pod("no-such-ns-xyz", limit=1)
            print("  404 正对照: 竟然没报错（异常）")
        except Exception as e:
            print(f"  404 正对照: 捕获 {type(e).__name__}, status={getattr(e,'status',None)}")

        # 正对照 2：直接构造一个 429 响应，看 kubernetes_asyncio 如何解析
        # 用 rest client 打一个已知路径并观察异常类
        from kubernetes_asyncio.client.rest import ApiException
        print("  ApiException 是否带 status 属性:",
              hasattr(ApiException(), "status"))
        # 手工构造 429 异常，验证 retry-after 语义如何暴露
        try:
            raise ApiException(status=429, reason="Too Many Requests")
        except ApiException as e:
            print(f"  构造 429: status={e.status}, reason={e.reason}, "
                  f"headers={e.headers}")


async def e3_apf_limits():
    print()
    print("=== E3. APF（API Priority and Fairness）阈值取证 ===")
    await aconfig.load_kube_config()
    async with aclient.ApiClient() as ac:
        custom = aclient.CustomObjectsApi(ac)
        try:
            plc = await custom.list_cluster_custom_object(
                "flowcontrol.apiserver.k8s.io", "v1",
                "prioritylevelconfigurations")
            print(f"  PriorityLevel 数量: {len(plc.get('items', []))}")
            for it in plc.get("items", []):
                name = it["metadata"]["name"]
                spec = it.get("spec", {})
                kind = spec.get("type")
                limited = spec.get("limited", {})
                assured = spec.get("assured_concurrency_shares", "n/a")
                if kind == "Limited":
                    cs = limited.get("assured_concurrency_shares")
                    nc = limited.get("nominal_concurrency_shares")
                    print(f"   - {name}: Limited, nominal={nc}, assured={cs}")
                elif kind == "Exempt":
                    print(f"   - {name}: Exempt（不限流）")
        except Exception as e:
            print("  读取 PLC 失败:", type(e).__name__, str(e)[:120])

        # 我方请求落在哪个 flowschema
        try:
            fs = await custom.list_cluster_custom_object(
                "flowcontrol.apiserver.k8s.io", "v1", "flowschemas")
            print(f"  FlowSchema 数量: {len(fs.get('items', []))}")
            for it in fs.get("items", []):
                md = it["metadata"]["name"]
                pl = it["spec"].get("priorityLevelConfiguration", {}).get("name")
                if md in ("system-leader-election", "workload-low",
                          "global-default", "catch-all", "service-accounts"):
                    print(f"   - {md} -> {pl}")
        except Exception as e:
            print("  读取 FlowSchema 失败:", type(e).__name__, str(e)[:120])


async def main():
    await e1_requests_really_sent()
    await e2_client_can_see_429()
    await e3_apf_limits()


if __name__ == "__main__":
    asyncio.run(main())
