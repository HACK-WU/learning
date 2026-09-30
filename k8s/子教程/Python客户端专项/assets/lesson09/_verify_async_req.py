"""先核验测量方法：CoreV1Api(api_client) 到底有没有用上我传的 ApiClient？

嫌疑1: CoreV1Api(api_client) 是否真的持有传入的 api_client？
嫌疑2: pool_threads 属性是否真的是 16？
嫌疑3: apply_async 到底走不走 pool？看 api_client.py 源码
"""
from kubernetes import client, config

config.load_kube_config()

print("=" * 64)
print("核验 1：CoreV1Api(api_client) 是否持有传入对象")
print("=" * 64)
ac16 = client.ApiClient(pool_threads=16)
api = client.CoreV1Api(ac16)
print(f"ac16 是 ApiClient: {isinstance(ac16, client.ApiClient)}")
print(f"ac16.pool_threads = {ac16.pool_threads}")
print(f"api.api_client is ac16 ? {api.api_client is ac16}")
print(f"api.api_client.pool_threads = {api.api_client.pool_threads}")

print("\n对比：不传参的默认情况")
api_d = client.CoreV1Api()
print(f"默认 api.api_client = {type(api_d.api_client).__name__}")
print(f"默认 pool_threads = {api_d.api_client.pool_threads}")

print()
print("\n核验 2：async_req=True 时源码走哪条路")
print("-" * 64)
import inspect
from kubernetes.client import api_client
src = inspect.getsource(api_client.ApiClient.call_api)
for line in src.splitlines():
    s = line.strip()
    if any(k in s for k in ("async_req", "pool", "apply_async", "return ")):
        print(f"  {s}")

print()
print("=" * 64)
print("核验 3：pool 属性是懒加载，_pool 初始为 None？")
print("=" * 64)
ac_fresh = client.ApiClient(pool_threads=16)
print(f"新建 ApiClient(16)._pool = {ac_fresh._pool}")
_ = ac_fresh.pool
print(f"访问 .pool 后 _pool = {ac_fresh._pool}")
print(f"该 ThreadPool 实际线程数 = {ac_fresh._pool._processes if hasattr(ac_fresh._pool, '_processes') else '?'}")
