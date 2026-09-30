"""补测：A3 完整异常消息 + A4 connector 真实属性名

上一轮两个取证不完整：
- A3 RuntimeError 消息被截断，看不到根因
- A4 取 connector 用了猜的属性名，得 None

按铁律：核验方法本身要对。
"""
import asyncio
import concurrent.futures

from kubernetes_asyncio import client as aclient
from kubernetes_asyncio import config as aconfig

NS = "default"


async def a3_full():
    print("=== A3 完整异常（跨线程跨 loop 复用同一 ApiClient）===")
    await aconfig.load_kube_config()
    ac = aclient.ApiClient()
    api = aclient.CoreV1Api(ac)
    loop = asyncio.get_running_loop()

    def run_new_loop():
        async def inner():
            await api.list_namespaced_pod(NS, limit=1)
            return "ok"
        new_loop = asyncio.new_event_loop()
        asyncio.set_event_loop(new_loop)
        try:
            return new_loop.run_until_complete(inner())
        except Exception as e:
            import traceback
            tb = traceback.format_exc().splitlines()
            # 只取最后几行与关键行
            keep = [l for l in tb if ("Error" in l or "loop" in l.lower()
                                      or "attached" in l)]
            return "\n".join(keep[:12])
        finally:
            new_loop.close()

    with concurrent.futures.ThreadPoolExecutor(max_workers=1) as ex:
        r = await loop.run_in_executor(ex, run_new_loop)
    print(r)

    print()
    print("=== A3b. 反证：在线程里新建 loop 并新建 ApiClient（应成功）===")

    def run_new_loop_new_client():
        async def inner():
            await aconfig.load_kube_config()
            async with aclient.ApiClient() as ac2:
                api2 = aclient.CoreV1Api(ac2)
                r = await api2.list_namespaced_pod(NS, limit=1)
                return f"成功, items={len(r.items)}"
        new_loop = asyncio.new_event_loop()
        asyncio.set_event_loop(new_loop)
        try:
            return new_loop.run_until_complete(inner())
        except Exception as e:
            return f"{type(e).__name__}: {str(e)[:200]}"
        finally:
            new_loop.close()

    with concurrent.futures.ThreadPoolExecutor(max_workers=1) as ex:
        r2 = await loop.run_in_executor(ex, run_new_loop_new_client)
    print(r2)

    await ac.close()


async def a4_connector():
    print()
    print("=== A4 connector 真实属性 ===")
    await aconfig.load_kube_config()
    ac = aclient.ApiClient()
    rc = ac.rest_client
    print("rest_client 全部属性:", [a for a in vars(rc) if not a.startswith("__")])

    # 找 connector / session
    for name in vars(rc):
        v = getattr(rc, name)
        tn = type(v).__name__
        if "onnector" in tn or "ession" in tn:
            print(f"  {name}: {tn} closed={getattr(v, 'closed', 'n/a')}")

    before = [getattr(getattr(rc, n), "closed", None)
              for n in vars(rc)
              if "onnector" in type(getattr(rc, n)).__name__
              or "ession" in type(getattr(rc, n)).__name__]
    print("close 前 closed 状态:", before)
    await ac.close()
    after = [getattr(getattr(rc, n), "closed", None)
             for n in vars(rc)
             if "onnector" in type(getattr(rc, n)).__name__
             or "ession" in type(getattr(rc, n)).__name__]
    print("close 后 closed 状态:", after)

    print()
    print("=== A4b. 双重关闭是否幂等 ===")
    try:
        await ac.close()
        print("二次 close: OK（幂等）")
    except Exception as e:
        print("二次 close:", type(e).__name__, str(e)[:120])


async def main():
    await a3_full()
    await a4_connector()


if __name__ == "__main__":
    asyncio.run(main())
