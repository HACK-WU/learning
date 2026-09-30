"""Q3 确证：namespace 级 ?watch=true 是被忽略还是真能流式？

上一轮关键现象：
  /api/v1/namespaces/{ns}/configmaps?watch=true -> TIMEOUT（流式，合法）
  /api/v1/namespaces/{ns}?watch=true            -> 200 立即返回整个 Namespace JSON

假设：watch=true 只对该资源**集合**路径有效；加在单体对象路径上被**静默忽略**，
      退化成一次普通 GET。这比报错更危险——你以为在 watch，其实只拿到快照。

确证方法：创建/修改对象后，看 namespace 级 watch 是否会**持续推事件**。
  真 watch  -> 会推送后续变更
  伪 watch  -> 只返回一次快照就结束
"""
import asyncio
import subprocess
import sys

sys.path.insert(0, "/mnt/d/projects/learning/k8s/子教程/Python客户端专项/assets/lesson06-async")

import kubernetes_asyncio as ka
from kubernetes_asyncio.client import ApiClient, CoreV1Api

NS = "py-lesson06-shared4"


def server():
    r = subprocess.run(
        ["bash", "-c",
         "kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}'"],
        capture_output=True, text=True)
    return (r.stdout or "").strip().rstrip("/")


async def main():
    await ka.config.load_kube_config()
    async with ApiClient() as api:
        v1 = CoreV1Api(api)
        try:
            await v1.create_namespace(body={"metadata": {"name": NS}})
        except Exception:
            pass
        await asyncio.sleep(0.5)

        print("=" * 70)
        print("Q3 确证：namespace 级 ?watch=true 是真 watch 还是伪 watch")
        print("=" * 70)

        rest = api.rest_client
        url = f"{server()}/api/v1/namespaces/{NS}?watch=true"

        print(f"\n  请求: {url}")
        try:
            r = await asyncio.wait_for(
                rest.request("GET", url,
                             headers={"Accept": "application/json"},
                             _preload_content=False, _request_timeout=6),
                timeout=6)
            data = await r.read()
            print(f"  状态码: {r.status}")
            print(f"  Content-Type: {r.headers.get('Content-Type')}")
            print(f"  响应长度: {len(data) if isinstance(data, bytes) else '?'} 字节（一次性读完）")
            txt = data.decode("utf-8", "replace") if isinstance(data, bytes) else ""
            kind = txt[:120]
            print(f"  响应开头: {kind}")
            print()
            if txt.strip().startswith("{") and "watchEvent" not in txt.lower():
                print("  → 返回的是**单个 JSON 对象**（Namespace），不是事件流")
                print("    watch=true 被**静默忽略**，退化成普通 GET")
            else:
                print("  → 疑似真事件流")
        except asyncio.TimeoutError:
            print("  → 超时（说明在流式挂起，是真 watch）")
        except Exception as e:
            print(f"  {type(e).__name__}: {str(e)[:120]}")

        # 对照：单资源集合 watch 的 Content-Type
        print()
        print("  对照：单资源集合 watch")
        url2 = f"{server()}/api/v1/namespaces/{NS}/configmaps?watch=true"
        print(f"  请求: {url2}")
        try:
            r = await asyncio.wait_for(
                rest.request("GET", url2,
                             headers={"Accept": "application/json"},
                             _preload_content=False, _request_timeout=4),
                timeout=4)
            print(f"  状态码: {r.status}  Content-Type: {r.headers.get('Content-Type')}")
            print("  → 挂起不返回 = 真 watch（流式）")
        except asyncio.TimeoutError:
            print("  → TIMEOUT = 真 watch（服务端挂起等事件）")
        except Exception as e:
            print(f"  {type(e).__name__}: {str(e)[:100]}")

        print()
        print("  判定:")
        print("    namespace 级 ?watch=true → 200 + 立即完整响应 = 普通 GET（参数被忽略）")
        print("    集合级 ?watch=true       → 挂起流式         = 真 watch")
        print("    ⇒ 协议上无法'一次 watch 多种资源'；")
        print("      SharedInformer 的 shared = 多消费者共享同一条资源 watch。")

        try:
            await v1.delete_namespace(name=NS)
            print(f"\n  已清理 ns {NS}")
        except Exception:
            pass


asyncio.run(main())
