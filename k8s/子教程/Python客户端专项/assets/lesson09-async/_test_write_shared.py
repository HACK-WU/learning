"""课 9 番外 · 实测 B：写操作并发共享 client 的安全性（未实测项 1）

课 9 已测：只读共享 10/10 零报错。本节课未测的**写路径**。

设计（区分三种"共享"，此前容易混为一谈）：
  S1 共享 ApiClient + 共享 Api 对象，多协程并发写不同对象
  S2 共享 ApiClient + 共享 Api 对象，多协程并发写**同一**对象（会撞 409）
  S3 每协程独立 ApiClient（对照基线）

判据：
  - 是否抛异常（尤其是底层连接/SSL/状态串扰类）
  - 最终结果是否与预期一致（不是"没报错"就算过）
  - 是否有静默错乱（写进去的值与提交的值不符）

注意：避免"实验污染"（课 7 番外教训）—— 每轮前清空 ns，删除后轮询等真正消失。
"""
import asyncio
import time

from kubernetes_asyncio import client as aclient
from kubernetes_asyncio import config as aconfig

NS = "py-lesson09-write"


async def ensure_ns(api_core, name):
    try:
        await api_core.create_namespace(
            aclient.V1Namespace(metadata=aclient.V1ObjectMeta(name=name)))
        print(f"  创建 ns {name}")
    except Exception as e:
        if "AlreadyExists" in str(e) or getattr(e, "status", None) == 409:
            print(f"  ns {name} 已存在，先清空")
        else:
            raise
    # 清空已有 ConfigMap
    try:
        cms = await api_core.list_namespaced_config_map(name)
        for cm in cms.items:
            await api_core.delete_namespaced_config_map(cm.metadata.name, name)
    except Exception as e:
        print("  清理失败:", type(e).__name__, str(e)[:80])


async def wait_gone(api_core, name):
    """删除后轮询等待真正消失（课 7 番外教训）"""
    for _ in range(60):
        try:
            await api_core.read_namespace(name)
        except Exception:
            return True
        await asyncio.sleep(0.5)
    return False


async def cleanup_ns(api_core, name):
    try:
        await api_core.delete_namespace(name)
    except Exception:
        pass
    await wait_gone(api_core, name)


async def create_cm(api_core, name, value):
    body = aclient.V1ConfigMap(
        metadata=aclient.V1ObjectMeta(name=name),
        data={"v": value},
    )
    return await api_core.create_namespaced_config_map(NS, body)


async def s1_shared_write_distinct():
    print("=== S1. 共享 ApiClient，多协程并发写【不同】对象 ===")
    await aconfig.load_kube_config()
    async with aclient.ApiClient() as ac:
        core = aclient.CoreV1Api(ac)
        await ensure_ns(core, NS)
        N = 20
        t0 = time.perf_counter()
        results = await asyncio.gather(
            *[create_cm(core, f"cm-{i:03d}", f"val-{i}") for i in range(N)],
            return_exceptions=True,
        )
        dt = time.perf_counter() - t0
        ok = [r for r in results if not isinstance(r, BaseException)]
        errs = [(type(r).__name__, str(r)[:90])
                for r in results if isinstance(r, BaseException)]
        print(f"  并发 {N} 次 create（不同名）: 成功 {len(ok)}/{N}, 耗时 {dt:.3f}s")
        for e in errs[:3]:
            print("   错误:", e)

        # 核验：值是否都写对了（防静默错乱）
        cms = await core.list_namespaced_config_map(NS)
        got = {cm.metadata.name: cm.data.get("v") for cm in cms.items}
        expect = {f"cm-{i:03d}": f"val-{i}" for i in range(N)}
        mismatch = {k: (got.get(k), v) for k, v in expect.items() if got.get(k) != v}
        print(f"  回读 {len(got)} 个, 值不符 {len(mismatch)} 个")
        if mismatch:
            print("   样例:", list(mismatch.items())[:3])
        await cleanup_ns(core, NS)


async def s2_shared_write_same():
    print()
    print("=== S2. 共享 ApiClient，多协程并发写【同一】对象 ===")
    await aconfig.load_kube_config()
    async with aclient.ApiClient() as ac:
        core = aclient.CoreV1Api(ac)
        await ensure_ns(core, NS)
        N = 10
        results = await asyncio.gather(
            *[create_cm(core, "cm-same", f"val-{i}") for i in range(N)],
            return_exceptions=True,
        )
        codes = []
        for r in results:
            if isinstance(r, BaseException):
                codes.append(getattr(r, "status", type(r).__name__))
            else:
                codes.append("OK")
        from collections import Counter
        print(f"  并发 {N} 次 create（同名）: {dict(Counter(codes))}")

        # 回读确认只有一个
        try:
            cm = await core.read_namespaced_config_map("cm-same", NS)
            print(f"  回读: 存在, v={cm.data.get('v')}")
        except Exception as e:
            print("  回读失败:", type(e).__name__, str(e)[:80])
        await cleanup_ns(core, NS)


async def s3_independent_clients():
    print()
    print("=== S3. 每协程独立 ApiClient（对照基线）===")
    await aconfig.load_kube_config()
    async with aclient.ApiClient() as ac0:
        core0 = aclient.CoreV1Api(ac0)
        await ensure_ns(core0, NS)

    N = 20

    async def one(i):
        async with aclient.ApiClient() as ac:
            core = aclient.CoreV1Api(ac)
            return await create_cm(core, f"cm-i-{i:03d}", f"val-{i}")

    t0 = time.perf_counter()
    results = await asyncio.gather(*[one(i) for i in range(N)],
                                   return_exceptions=True)
    dt = time.perf_counter() - t0
    ok = [r for r in results if not isinstance(r, BaseException)]
    errs = [(type(r).__name__, str(r)[:90])
            for r in results if isinstance(r, BaseException)]
    print(f"  并发 {N} 次 create（各自 client）: 成功 {len(ok)}/{N}, 耗时 {dt:.3f}s")
    for e in errs[:3]:
        print("   错误:", e)

    async with aclient.ApiClient() as ac:
        core = aclient.CoreV1Api(ac)
        cms = await core.list_namespaced_config_map(NS)
        print(f"  回读 {len(cms.items)} 个")
        await cleanup_ns(core, NS)


async def s4_patch_same_object():
    print()
    print("=== S4. 共享 client 并发 patch【同一】对象（真实控制器场景）===")
    await aconfig.load_kube_config()
    async with aclient.ApiClient() as ac:
        core = aclient.CoreV1Api(ac)
        await ensure_ns(core, NS)
        await create_cm(core, "cm-patch", "init")
        N = 15
        results = await asyncio.gather(
            *[core.patch_namespaced_config_map(
                "cm-patch", NS,
                {"data": {f"k{i:02d}": f"v{i}"}}) for i in range(N)],
            return_exceptions=True,
        )
        codes = []
        for r in results:
            if isinstance(r, BaseException):
                codes.append(getattr(r, "status", type(r).__name__))
            else:
                codes.append("OK")
        from collections import Counter
        print(f"  并发 {N} 次 patch（同一对象不同 key）: {dict(Counter(codes))}")
        cm = await core.read_namespaced_config_map("cm-patch", NS)
        print(f"  回读 data 键数: {len(cm.data)}（含 init={cm.data.get('v')}）")
        await cleanup_ns(core, NS)


async def main():
    await s1_shared_write_distinct()
    await s2_shared_write_same()
    await s3_independent_clients()
    await s4_patch_same_object()


if __name__ == "__main__":
    asyncio.run(main())
