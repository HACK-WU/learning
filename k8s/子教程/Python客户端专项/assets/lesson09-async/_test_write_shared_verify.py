"""核验：S1/S3 回读 21 个 vs 写入 20 个，多出的那 1 个是什么？

按铁律：数字对不上先怀疑测量方法，别急着下结论。
可能：① ns 被复用带了历史残留 ② k8s 自动注入的 kube-root-ca.crt
"""
import asyncio

from kubernetes_asyncio import client as aclient
from kubernetes_asyncio import config as aconfig

NS = "py-lesson09-write"


async def main():
    await aconfig.load_kube_config()
    async with aclient.ApiClient() as ac:
        core = aclient.CoreV1Api(ac)
        try:
            await core.create_namespace(
                aclient.V1Namespace(metadata=aclient.V1ObjectMeta(name=NS)))
            print(f"创建 ns {NS}")
        except Exception as e:
            print("创建 ns:", type(e).__name__, str(e)[:60])

        await asyncio.sleep(1.0)
        cms = await core.list_namespaced_config_map(NS)
        print(f"【空 ns 里已有的 ConfigMap】共 {len(cms.items)} 个:")
        for cm in cms.items:
            print(f"  - {cm.metadata.name}  (data keys={list(cm.data or {})})")

        # 清理
        await core.delete_namespace(NS)
        for _ in range(60):
            try:
                await core.read_namespace(NS)
            except Exception:
                print("ns 已真正删除")
                break
            await asyncio.sleep(0.5)
        else:
            print("警告: ns 未能在 30s 内删除")


if __name__ == "__main__":
    asyncio.run(main())
