"""课 9 开篇：异步包版本核实 + 兼容性实测（修正版）

坑 1：kubernetes_asyncio.config.load_kube_config 是 async def！
       同步包里它是普通函数，照抄 `config.load_kube_config()` 只给一个
       RuntimeWarning，然后 host 为空 → InvalidUrlClientError: /version/
       没有任何显式报错，属于"挂了但看起来没挂"
"""
import asyncio

import kubernetes_asyncio as ka

print("=" * 64)
print("版本核实")
print("=" * 64)
print(f"kubernetes_asyncio.__version__ = {getattr(ka, '__version__', '?')}")

import kubernetes as ksync
print(f"同步 kubernetes.__version__     = {ksync.__version__}")

print("\n异步包子模块：")
import pkgutil
print(f"  {[m.name for m in pkgutil.iter_modules(ka.__path__)]}")

print("\n" + "=" * 64)
print("坑 1 验证：load_kube_config 是协程吗？")
print("=" * 64)
import inspect
print(f"  load_kube_config 是协程函数: {inspect.iscoroutinefunction(ka.config.load_kube_config)}")
print(f"  new_client_from_config 是协程函数: {inspect.iscoroutinefunction(ka.config.new_client_from_config)}")
print(f"  load_incluster_config 是协程函数: {inspect.iscoroutinefunction(ka.config.load_incluster_config)}")

print("\n" + "=" * 64)
print("兼容性实测：能不能真连上 v1.34.0 集群")
print("=" * 64)


async def main():
    # 正确写法：await
    await ka.config.load_kube_config()

    async with ka.client.ApiClient() as api:
        v1 = ka.client.CoreV1Api(api)

        ver = await ka.client.VersionApi(api).get_code()
        print(f"  server gitVersion  = {ver.git_version}")
        print(f"  server major.minor = {ver.major}.{ver.minor}")

        ret = await v1.list_pod_for_all_namespaces()
        print(f"  list_pod_for_all_namespaces -> {len(ret.items)} pods")

        ns = await v1.list_namespace()
        print(f"  list_namespace -> {len(ns.items)} ns")

        if ret.items:
            p = ret.items[0]
            print(f"  首个 Pod 类型 = {type(p).__module__}.{type(p).__name__}")
            print(f"  首个 Pod 名   = {p.metadata.name}")

    print("\n  async with 已退出")
    return len(ret.items)


n = asyncio.run(main())
print(f"\n结论：kubernetes-asyncio 36.1.0 对 v1.34.0 集群可用，实跑拿到 {n} pods")
