"""Q3 三次重做：借用 kubernetes_asyncio 自己的 rest 客户端发 RAW 请求

前两次失败原因：
  1. call_api(response_type=...) -> TypeError（参数不存在）
  2. aiohttp 直连 -> SSLCertVerificationError（没带集群 CA）

这次用库内已配好 SSL 的 RESTClientObject 直接发，
对比「单资源 path」与「namespace 级 path」的真实状态码。
"""
import asyncio
import subprocess
import sys

sys.path.insert(0, "/mnt/d/projects/learning/k8s/子教程/Python客户端专项/assets/lesson06-async")

import kubernetes_asyncio as ka
from kubernetes_asyncio.client import ApiClient, CoreV1Api
from kubernetes_asyncio.client.rest import ApiException

NS = "py-lesson06-shared3"


def server():
    r = subprocess.run(
        ["bash", "-c",
         "kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}'"],
        capture_output=True, text=True)
    return (r.stdout or "").strip().rstrip("/")


async def raw_get(api, path, timeout=4):
    """用库内 REST 客户端发一条 GET，返回 (status, body前缀)"""
    rest = api.rest_client
    try:
        r = await asyncio.wait_for(
            rest.request("GET", server() + path,
                         headers={"Accept": "application/json"},
                         _preload_content=False,
                         _request_timeout=timeout),
            timeout=timeout)
        # _preload_content=False 时返回 aiohttp.ClientResponse，read() 不带参数
        try:
            data = await r.read()
        except TypeError:
            data = b""
        if isinstance(data, bytes) and len(data) > 200:
            data = data[:200]
        return r.status, data[:200]
    except asyncio.TimeoutError:
        return "TIMEOUT(流式)", b""
    except ApiException as e:
        return e.status, str(e)[:120].encode()
    except Exception as e:
        return type(e).__name__, str(e)[:120].encode()


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
        print("Q3：watch path 能否覆盖多种资源？（RAW 请求实测）")
        print("=" * 70)
        print(f"  server = {server()}\n")

        cases = [
            (f"/api/v1/namespaces/{NS}/configmaps?watch=true",
             "单资源 configmaps watch"),
            (f"/api/v1/namespaces/{NS}/secrets?watch=true",
             "单资源 secrets watch"),
            (f"/api/v1/namespaces/{NS}?watch=true",
             "namespace 级 watch（想一次看多种）"),
            (f"/api/v1/watch/namespaces/{NS}",
             "旧式 watch path"),
        ]
        for path, desc in cases:
            st, body = await raw_get(api, path)
            mark = "✓合法" if st in (200, "TIMEOUT(流式)") else "✗不支持"
            print(f"  [{mark}] {desc}")
            print(f"           path = {path}")
            print(f"           返回 = {st}  {body[:110]!r}")
            print()

        # 反向验证：确认单资源 watch 确实能推事件
        print("  反向验证：单资源 watch 真的能收到事件吗？")
        await v1.create_namespaced_config_map(
            namespace=NS,
            body={"metadata": {"name": "probe"}, "data": {"k": "v"}})
        st, body = await raw_get(api,
                                 f"/api/v1/namespaces/{NS}/configmaps?watch=true")
        print(f"           单资源 watch 状态: {st}  body={body[:80]!r}")

        try:
            await v1.delete_namespace(name=NS)
            print(f"\n  已清理 ns {NS}")
        except Exception:
            pass


asyncio.run(main())
