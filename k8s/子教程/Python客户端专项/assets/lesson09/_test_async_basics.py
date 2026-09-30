"""课 9 知识点 1：异步客户端形态差异

要实测的点：
1. 方法名是否同名（同名 → 迁移只加 await）
2. 忘了 await 会怎样（协程对象不报错，静默不执行）
3. async with ApiClient() 到底关了什么 —— 不关会怎样（连接泄漏）
4. load_incluster_config 不是协程（与另外两个不一致）
5. async_req 参数在异步包里还在不在（应在：语义已被 await 取代）
"""
import asyncio
import gc
import warnings

import kubernetes_asyncio as ka
from kubernetes_asyncio.client import ApiClient, CoreV1Api

print("=" * 64)
print("1. 方法名对比：同步 vs 异步是否同名")
print("=" * 64)
import kubernetes as ksync
sync_names = {n for n in dir(ksync.client.CoreV1Api) if not n.startswith("_")}
async_names = {n for n in dir(ka.client.CoreV1Api) if not n.startswith("_")}
print(f"  同步 CoreV1Api 方法数: {len(sync_names)}")
print(f"  异步 CoreV1Api 方法数: {len(async_names)}")
print(f"  同名方法数: {len(sync_names & async_names)}")
only_sync = sorted(sync_names - async_names)[:8]
only_async = sorted(async_names - sync_names)[:8]
print(f"  仅同步有(前8): {only_sync}")
print(f"  仅异步有(前8): {only_async}")

print("\n  async_req 相关方法还在吗？")
ar = [n for n in async_names if "async" in n.lower()]
print(f"    {ar if ar else '无（async_req 已由 await 取代，方法级无此概念）'}")

print()
print("=" * 64)
print("2. 忘了 await 会怎样 —— 静默失效演示")
print("=" * 64)


async def demo_no_await():
    await ka.config.load_kube_config()
    async with ApiClient() as api:
        v1 = CoreV1Api(api)
        coro = v1.list_pod_for_all_namespaces()   # 忘了 await
        print(f"  返回类型: {type(coro).__name__}")
        print(f"  是协程对象: {__import__('inspect').iscoroutine(coro)}")
        print(f"  -> 请求根本没发出去，且不会报错")
        # 关掉协程避免 warning
        coro.close()
        print(f"  若直接当成结果用: len(coro) 会 TypeError")


asyncio.run(demo_no_await())

print()
print("=" * 64)
print("3. async with 到底关了什么 —— 不关的连接泄漏实测")
print("=" * 64)


async def demo_leak():
    await ka.config.load_kube_config()

    # A: 用 async with
    connectors_before = _count_connectors()
    async with ApiClient() as api:
        v1 = CoreV1Api(api)
        await v1.list_namespace()
    gc.collect()
    await asyncio.sleep(0.3)
    connectors_after_ctx = _count_connectors()
    print(f"  [async with] 退出后存活 connector 数: {connectors_after_ctx}")

    # B: 不用 async with，也不 close
    api2 = ApiClient()
    v2 = CoreV1Api(api2)
    await v2.list_namespace()
    gc.collect()
    await asyncio.sleep(0.3)
    connectors_leak = _count_connectors()
    print(f"  [裸用不关]   退出后存活 connector 数: {connectors_leak}")

    print(f"\n  差值 = {connectors_leak - connectors_after_ctx} (未关闭的连接器)")
    if connectors_leak > connectors_after_ctx:
        print("  -> 不关会留下未回收的 aiohttp 连接器（连接泄漏）")
    # 清理
    await api2.close()


def _count_connectors():
    """统计事件循环里存活的 aiohttp TCPConnector"""
    import aiohttp
    n = 0
    for obj in gc.get_objects():
        if isinstance(obj, aiohttp.TCPConnector):
            n += 1
    return n


asyncio.run(demo_leak())

print()
print("=" * 64)
print("4. 三个 config 函数的协程性不一致（易踩）")
print("=" * 64)
import inspect
for fn in ("load_kube_config", "new_client_from_config", "load_incluster_config"):
    f = getattr(ka.config, fn)
    print(f"  {fn:<28} 协程? {inspect.iscoroutinefunction(f)}")
print("  -> load_incluster_config 是唯一非协程（同步包里三个都是普通函数）")
