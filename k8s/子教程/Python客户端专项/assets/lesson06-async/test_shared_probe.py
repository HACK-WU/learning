"""验证 7：SharedInformer 的立论基础核验

课 6 §7.2 声称：
  1. 每个 watch 独占一条 TCP 连接
  2. 资源种类多了会耗尽连接池

本番外要实现「复用单条连接 watch 多资源」，必须先确认：
  Q1: N 个并发 watch 到底是不是 N 条 TCP 连接？（计数 ESTABLISHED）
  Q2: 有没有办法让多个 watch 复用？HTTP/1.1 还是 HTTP/2？
  Q3: 连接池上限是多少？真的会"耗尽"吗？

⚠️ 不实测就照抄课 6 的结论，是本课程反复犯的错。
"""
import asyncio
import re
import subprocess
import sys
import time

sys.path.insert(0, "/mnt/d/projects/learning/k8s/子教程/Python客户端专项/assets/lesson06-async")

import kubernetes_asyncio as ka
from kubernetes_asyncio.client import ApiClient, CoreV1Api

NS = "py-lesson06-shared"


# ⚠️ 测法修正（2026-09-29）：
#   第一版硬编码 6443，实测恒为 0 —— 因为这是 kind 集群，
#   apiserver 端口转发到 127.0.0.1:45145（实测 kubeconfig server）。
#   "数到 0" 不是"没有连接"，是**数错了地方**。
def _apiport():
    r = subprocess.run(
        ["bash", "-c",
         "kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}'"],
        capture_output=True, text=True)
    m = re.search(r":(\d+)\s*$", (r.stdout or "").strip())
    return m.group(1) if m else "6443"


APIPORT = _apiport()


def count_established():
    """数到 apiserver 的 ESTABLISHED 连接数（客户端本地端口连接过去）"""
    r = subprocess.run(
        ["bash", "-c",
         f"ss -tn state established '( dport = :{APIPORT} )' | tail -n +2 | wc -l"],
        capture_output=True, text=True)
    try:
        return int((r.stdout or "0").strip().splitlines()[0])
    except Exception:
        return -1


def count_all_6443():
    r = subprocess.run(
        ["bash", "-c",
         f"ss -tn '( dport = :{APIPORT} )' | tail -n +2 | wc -l"],
        capture_output=True, text=True)
    try:
        return int((r.stdout or "0").strip().splitlines()[0])
    except Exception:
        return -1


async def setup(v1):
    try:
        await v1.create_namespace(body={"metadata": {"name": NS}})
    except Exception:
        pass
    await asyncio.sleep(0.3)


async def hold_watch(idx, list_fn, stop_ev):
    """维持一个 watch 直到 stop_ev"""
    w = ka.watch.Watch()
    async with w:
        try:
            async for e in w.stream(list_fn, namespace=NS,
                                    timeout_seconds=2,
                                    _request_timeout=6):
                if stop_ev.is_set():
                    break
        except Exception:
            pass
        # 持续重连，保持连接活着
        while not stop_ev.is_set():
            try:
                async for e in w.stream(list_fn, namespace=NS,
                                        timeout_seconds=2,
                                        _request_timeout=6):
                    if stop_ev.is_set():
                        break
            except Exception:
                pass
            await asyncio.sleep(0.1)


async def measure(n, label):
    await ka.config.load_kube_config()
    async with ApiClient() as api:
        v1 = CoreV1Api(api)
        await setup(v1)
        await asyncio.sleep(0.5)

        base = count_established()
        stop_ev = asyncio.Event()
        fns = [v1.list_namespaced_config_map,
               v1.list_namespaced_secret,
               v1.list_namespaced_pod,
               v1.list_namespaced_service]
        tasks = [asyncio.create_task(hold_watch(i, fns[i % 4], stop_ev))
                 for i in range(n)]
        await asyncio.sleep(3.0)
        during_est = count_established()
        during_all = count_all_6443()
        stop_ev.set()
        for t in tasks:
            t.cancel()
        await asyncio.gather(*tasks, return_exceptions=True)
        await asyncio.sleep(1.0)
        after = count_established()

        print(f"  {label} n={n}:")
        print(f"    基线 ESTABLISHED = {base}")
        print(f"    watch 期间        = {during_est}  (全部 6443: {during_all})")
        print(f"    停止后            = {after}")
        print(f"    → 新增连接数      = {during_est - base}")
        return n, during_est - base


async def main():
    print("=" * 70)
    print("Q1: N 个并发 watch = N 条 TCP 连接？")
    print("=" * 70)
    print(f"  (apisterver 实际端口 = {APIPORT}，用 ss 数 dport 的 ESTABLISHED)\n")

    results = []
    for n in (1, 2, 4, 8):
        r = await measure(n, "  ")
        results.append(r)
    print()
    print("  汇总:")
    for n, delta in results:
        ratio = delta / n if n else 0
        print(f"    n={n:<2} 新增连接={delta:<3} 连接/资源={ratio:.2f}")

    print()
    print("=" * 70)
    print("Q2: 客户端连接池上限（aiohttp 默认）")
    print("=" * 70)
    import aiohttp
    print()
    print("  aiohttp 默认 limit          = "
          f"{getattr(aiohttp.helpers, 'DEFAULT_LIMIT', '?')}")
    print("  aiohttp 默认 limit_per_host = "
          f"{getattr(aiohttp.helpers, 'DEFAULT_LIMIT_PER_HOST', '?')}")
    conn = aiohttp.TCPConnector()
    print(f"  TCPConnector 实际 limit          = {conn.limit}")
    print(f"  TCPConnector 实际 limit_per_host = {conn.limit_per_host}")
    await conn.close()
    print()
    print("  → limit_per_host 默认 0 = 不限，所以 aiohttp 侧**不会**耗尽；")
    print("    真正的约束是 fd 上限与 apiserver 侧连接/并发限制。")
    print("    课 6 说的'耗尽连接池'应理解为**资源线性增长**，而非撞到硬上限。")

    print()
    print("=" * 70)
    print("Q3: 单 ApiClient 内多个 watch 是否复用连接？")
    print("=" * 70)
    await ka.config.load_kube_config()
    async with ApiClient() as api:
        v1 = CoreV1Api(api)
        base = count_established()
        stop_ev = asyncio.Event()
        # 同一个 api → 同一个 aiohttp session → 同一个 connector
        tasks = [asyncio.create_task(
            hold_watch(i, [v1.list_namespaced_config_map,
                           v1.list_namespaced_secret,
                           v1.list_namespaced_pod,
                           v1.list_namespaced_service][i % 4], stop_ev))
            for i in range(4)]
        await asyncio.sleep(3.0)
        during = count_established()
        stop_ev.set()
        for t in tasks:
            t.cancel()
        await asyncio.gather(*tasks, return_exceptions=True)
        await asyncio.sleep(1.0)
        print(f"    单 ApiClient + 4 watch: 基线={base} 期间={during} "
              f"新增={during - base}")
        print()
        if during - base >= 4:
            print("    → 4 个 watch 用了 ≥4 条连接：**连接未被复用**")
            print("      HTTP/1.1 下一个流式响应必须独占连接，无法多路复用")
        else:
            print("    → 连接被复用（可能是 HTTP/2）")

    # 清理
    await ka.config.load_kube_config()
    async with ApiClient() as api:
        try:
            await CoreV1Api(api).delete_namespace(name=NS)
            print(f"\n  已清理 ns {NS}")
        except Exception as e:
            print(f"  清理: {type(e).__name__}")


asyncio.run(main())
