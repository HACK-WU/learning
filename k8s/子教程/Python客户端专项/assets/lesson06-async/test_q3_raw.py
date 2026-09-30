"""Q3 重做：用真实 HTTP 请求验证"能否一条连接 watch 多种资源"

上一版用 api.call_api 传了不存在的 response_type，TypeError，
等于**没测**。这次用 aiohttp 直接打 API，看真实 HTTP 状态码。
"""
import asyncio
import subprocess
import sys

sys.path.insert(0, "/mnt/d/projects/learning/k8s/子教程/Python客户端专项/assets/lesson06-async")

import aiohttp

import kubernetes_asyncio as ka
from kubernetes_asyncio.client import ApiClient, CoreV1Api

NS = "py-lesson06-shared2"


def server():
    r = subprocess.run(
        ["bash", "-c",
         "kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}'"],
        capture_output=True, text=True)
    return (r.stdout or "").strip()


async def main():
    await ka.config.load_kube_config()
    cfg = ka.client.Configuration.get_default_copy()
    base = server()

    print("=" * 70)
    print("Q3 重做：watch 的 path 能否覆盖多种资源？")
    print("=" * 70)
    print(f"  server = {base}\n")

    # 建 ns
    async with ApiClient() as api:
        v1 = CoreV1Api(api)
        try:
            await v1.create_namespace(body={"metadata": {"name": NS}})
        except Exception:
            pass

    ssl = None
    if cfg.ssl_ca_cert:
        ssl = aiohttp.TCPConnector(ssl=True)
    headers = {}
    if cfg.api_key and "authorization" in cfg.api_key:
        headers["Authorization"] = cfg.api_key["authorization"]

    paths = [
        (f"/api/v1/namespaces/{NS}/configmaps?watch=true",
         "单资源 configmaps（应 200）"),
        (f"/api/v1/namespaces/{NS}?watch=true",
         "namespace 级 watch（试探）"),
        (f"/api/v1/watch/namespaces/{NS}",
         "旧式 watch path（试探）"),
    ]

    conn = ssl or aiohttp.TCPConnector()
    async with aiohttp.ClientSession(connector=conn) as s:
        for p, desc in paths:
            url = base.rstrip("/") + p
            try:
                async with s.get(url, headers=headers,
                                 timeout=aiohttp.ClientTimeout(total=4)) as r:
                    # 只取状态码和前 200 字节，不等流结束
                    chunk = await r.content.read(200)
                    print(f"  [{r.status}] {desc}")
                    print(f"         {p}")
                    print(f"         body[:120] = {chunk[:120]!r}")
            except asyncio.TimeoutError:
                print(f"  [超时] {desc}  <- 说明服务端**接受了**并在流式推送")
                print(f"         {p}")
            except Exception as e:
                print(f"  [{type(e).__name__}] {desc}: {str(e)[:90]}")
            print()

    print("  判定依据:")
    print("    - 单资源 path 返回 200 或超时（流式）→ 合法")
    print("    - namespace 级 path 若返回 404/405/400 → 协议不支持多资源 watch")

    # 清理
    async with ApiClient() as api:
        try:
            await CoreV1Api(api).delete_namespace(name=NS)
            print(f"\n  已清理 ns {NS}")
        except Exception:
            pass


asyncio.run(main())
