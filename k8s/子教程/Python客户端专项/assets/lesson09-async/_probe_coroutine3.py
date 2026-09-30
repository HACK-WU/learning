"""探针 3：异步方法凭什么返回 coroutine？内部机制 + 参数名一致性

探针 2 已证：方法 def 是普通 function，但调用返回 coroutine。
本课查清：
1. 内部靠什么把普通 def 变成协程（找 async def / async_req / __call_api）
2. 同步 vs 异步的方法签名的参数名是否真的一致（课 9 说"只加 await"）
"""
import inspect
import re

from kubernetes.client.api import core_v1_api as s
from kubernetes_asyncio.client.api import core_v1_api as a

PAT = re.compile(r"async def|return |coroutine|__call_api|async_req|def _")


def dump(src, tag, maxline=200):
    print(f"=== {tag} ===")
    for i, l in enumerate(src.splitlines()[:maxline]):
        if PAT.search(l):
            print(f"{i:4d}| {l[:140]}")
    print()


def main():
    a_src = inspect.getsource(a.CoreV1Api.list_namespaced_pod)
    s_src = inspect.getsource(s.CoreV1Api.list_namespaced_pod)
    dump(a_src, "异步版")
    dump(s_src, "同步版")

    print("=== 异步版尾部 30 行（看 return 怎么写的）===")
    for i, l in enumerate(a_src.splitlines()[-30:]):
        print(f"{i:4d}| {l[:140]}")

    print()
    print("=== 同步版尾部 20 行 ===")
    for i, l in enumerate(s_src.splitlines()[-20:]):
        print(f"{i:4d}| {l[:140]}")

    print()
    print("=== 参数名一致性（inspect.signature）===")
    a_sig = inspect.signature(a.CoreV1Api.list_namespaced_pod)
    s_sig = inspect.signature(s.CoreV1Api.list_namespaced_pod)
    a_params = list(a_sig.parameters)
    s_params = list(s_sig.parameters)
    print("异步参数数:", len(a_params), " 同步参数数:", len(s_params))
    print("参数名完全一致:", a_params == s_params)
    if a_params != s_params:
        print("仅异步有:", set(a_params) - set(s_params))
        print("仅同步有:", set(s_params) - set(a_params))

    print()
    print("=== 逐个方法比对参数名（CoreV1Api 全部）===")
    diff = []
    checked = 0
    for n in dir(s.CoreV1Api):
        if n.startswith("_"):
            continue
        sf = getattr(s.CoreV1Api, n, None)
        af = getattr(a.CoreV1Api, n, None)
        if not inspect.isfunction(sf) or not inspect.isfunction(af):
            continue
        try:
            sp = list(inspect.signature(sf).parameters)
            ap = list(inspect.signature(af).parameters)
        except (TypeError, ValueError):
            continue
        checked += 1
        if sp != ap:
            diff.append((n, set(sp) ^ set(ap)))
    print("比对方法数:", checked)
    print("参数名有差异的方法数:", len(diff))
    for n, d in diff[:10]:
        print("  ", n, "->", sorted(d))


if __name__ == "__main__":
    main()
