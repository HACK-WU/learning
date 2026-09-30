"""番外 4：异步调谐的重试与退避 —— 立论核验

番外 1 的 reconcile_worker 现状：
    except Exception:
        stats["errors"] += 1      # ← 记一笔就丢了，对象不再入队

问题：
  Q1: 失败后对象就永久丢失了？（不重入队 = 状态漂移）
  Q2: 哪些错误值得重试？409/5xx/网络超时 分别该不该重试？
  Q3: 天真重试会怎样？（固定间隔 + 无上限 = 重试风暴）
  Q4: 指数退避 + jitter 是否真的打散了？（测实际间隔分布）

不实测就写讲义 = 违反本课程铁律。
"""
import asyncio
import random
import sys
import time
from collections import defaultdict

sys.path.insert(0, "/mnt/d/projects/learning/k8s/子教程/Python客户端专项/assets/lesson06-async")

import kubernetes_asyncio as ka
from kubernetes_asyncio.client import ApiClient, CoreV1Api
from kubernetes_asyncio.client.rest import ApiException

from async_controller import AsyncWorkQueueFixed, reconcile_one

NS = "py-lesson06-retry"


# ---------------------------------------------------------------- Q1

async def q1_loss():
    print("=" * 70)
    print("Q1: 调谐失败后对象会永久丢失吗？")
    print("=" * 70)
    await ka.config.load_kube_config()
    async with ApiClient() as api:
        v1 = CoreV1Api(api)
        try:
            await v1.create_namespace(body={"metadata": {"name": NS}})
        except Exception:
            pass
        await asyncio.sleep(0.4)

        stats = defaultdict(int)
        # 模拟：对象不存在（读 404）→ reconcile_one 记 gone 直接 return
        r1 = await reconcile_one(v1, NS, "never-exists", stats)
        print(f"\n  读不存在的对象: 返回={r1!r}  stats={dict(stats)}")
        print(f"  → 404 判为 gone 后**直接 return**，队列里再也不会有它")
        print("     对'刚被删的对象'这是对的（不该重试）；")
        print("     但对'临时 5xx/超时'如果也这么处理，对象就**永久漂移**了。")

        # 关键对比：区分 404 与 5xx 的处理是否相同
        print()
        print(f"  现有代码只 catch 了 404，其余 raise → 由 worker 的裸 except 吞掉")
        print(f"  即 5xx 与 404 最终**都被丢弃**，只是路径不同。")


# ---------------------------------------------------------------- Q2

async def q2_which_errors():
    print()
    print("=" * 70)
    print("Q2: 各类错误该不该重试？（实测 K8s 真实行为）")
    print("=" * 70)

    await ka.config.load_kube_config()
    async with ApiClient() as api:
        v1 = CoreV1Api(api)
        await asyncio.sleep(0.3)
        # 建一个基准对象
        try:
            await v1.create_namespaced_config_map(
                namespace=NS,
                body={"metadata": {"name": "retry-base"}, "data": {"k": "v"}})
        except Exception:
            pass

        print(f"\n  {'场景':<34} {'实测结果':<26} 判定")
        print(f"  {'-'*34} {'-'*26} {'-'*8}")

        # 1. 409 Conflict：用错误的 resourceVersion 触发
        obj = await v1.read_namespaced_config_map("retry-base", NS)
        try:
            await v1.replace_namespaced_config_map(
                name="retry-base", namespace=NS,
                body={"metadata": {"name": "retry-base",
                                   "resourceVersion": "999999999"},
                      "data": {"k": "v2"}})
            print(f"  {'replace 带旧 rv（期望409）':<34} {'没冲突?!':<26} ?")
        except ApiException as e:
            verdict = "重试有意义（重读 rv）" if e.status == 409 else "不该重试"
            print(f"  {'replace 带旧 rv':<34} {f'HTTP {e.status}':<26} {verdict}")

        # 2. 422 非法对象名
        try:
            await v1.create_namespaced_config_map(
                namespace=NS,
                body={"metadata": {"name": "BAD_NAME!!"}, "data": {}})
            print(f"  {'非法名称':<34} {'没报错?!':<26} ?")
        except ApiException as e:
            verdict = "不该重试（改代码才有用）" if e.status == 422 else "?"
            print(f"  {'非法名称 create':<34} {f'HTTP {e.status}':<26} {verdict}")

        # 3. 404 读不存在的
        try:
            await v1.read_namespaced_config_map("nope-xyz", NS)
        except ApiException as e:
            print(f"  {'读不存在的对象':<34} {f'HTTP {e.status}':<26} "
                  f"不该重试（对象已删）")

        # 4. 幂等验证：patch 两次
        s = defaultdict(int)
        a = await reconcile_one(v1, NS, "retry-base", s)
        b = await reconcile_one(v1, NS, "retry-base", s)
        print(f"  {'同对象连续调谐两次':<34} "
              f"{f'{a} → {b}':<26} "
              f"{'幂等' if b == 'no_op' else '!! 不幂等'}")

        print()
        print("  结论表:")
        print("    409 Conflict  → 重试（重读最新 rv 后再写）")
        print("    5xx / 超时    → 重试（服务端暂时不可用）")
        print("    404 NotFound  → 不重试（对象已删除，判 gone）")
        print("    422 / 400     → 不重试（请求本身错，重试无意义）")


# ---------------------------------------------------------------- Q3

async def q3_naive_retry():
    print()
    print("=" * 70)
    print("Q3: 天真重试（固定间隔 + 无上限）会怎样？")
    print("=" * 70)

    calls = defaultdict(int)

    async def always_fail(name):
        calls[name] += 1
        raise RuntimeError("永远失败")

    async def naive_worker(q, stop):
        """固定 0.1s 间隔，无限重试"""
        while not stop.is_set():
            try:
                name = await asyncio.wait_for(q.get(), timeout=0.2)
            except asyncio.TimeoutError:
                continue
            try:
                for _ in range(10000):        # 近乎无限
                    try:
                        await always_fail(name)
                        break
                    except Exception:
                        await asyncio.sleep(0.1)
            finally:
                q.done(name)

    q = AsyncWorkQueueFixed()
    stop = asyncio.Event()
    for i in range(5):
        q.add(f"obj-{i}")
    t = asyncio.create_task(naive_worker(q, stop))
    await asyncio.sleep(3.0)
    stop.set()
    t.cancel()
    try:
        await t
    except asyncio.CancelledError:
        pass

    total = sum(calls.values())
    print(f"\n  5 个失败对象，3 秒内总调用次数 = {total}")
    print(f"  平均每对象 {total/5:.0f} 次")
    print()
    print(f"  → 失败对象**永远占着 worker**，后面的对象排不上队")
    print(f"    这就是**队头阻塞**（head-of-line blocking）")
    print(f"    若失败率上升，worker 全部陷在重试里 → 整个控制器停摆")


# ---------------------------------------------------------------- Q4

async def q4_backoff():
    print()
    print("=" * 70)
    print("Q4: 指数退避 + jitter 实测间隔分布")
    print("=" * 70)

    def backoff_no_jitter(attempt, base=0.1, cap=5.0):
        return min(base * (2 ** attempt), cap)

    def backoff_equal_jitter(attempt, base=0.1, cap=5.0):
        """Equal Jitter: 一半固定 + 一半随机（AWS 推荐）"""
        v = min(base * (2 ** attempt), cap)
        return v / 2 + random.uniform(0, v / 2)

    print(f"\n  {'attempt':<9} {'无jitter':<12} {'equal-jitter(3次采样)':<34}")
    print(f"  {'-'*9} {'-'*12} {'-'*34}")
    for a in range(7):
        nj = backoff_no_jitter(a)
        sj = [backoff_equal_jitter(a) for _ in range(3)]
        s = "  ".join(f"{x:.3f}" for x in sj)
        print(f"  {a:<9} {nj:<12.3f} {s:<34}")

    # 关键：jitter 是否真的打散了「同一时刻的重试」
    print()
    print("  惊群验证：100 个对象同时失败，第 3 次重试的时刻分布")
    N = 100
    for label, fn in (("无 jitter", backoff_no_jitter),
                      ("equal jitter", backoff_equal_jitter)):
        # 前两次的累计 + 第三次
        times = [backoff_no_jitter(0) + backoff_no_jitter(1) + fn(2)
                 for _ in range(N)]
        span = max(times) - min(times)
        print(f"    {label:<14} 第3次重试时间跨度 = {span:.4f}s "
              f"(min={min(times):.3f} max={max(times):.3f})")
    print()
    print("  → 无 jitter 时跨度 0（100 个对象**同一瞬间**一起重试 = 惊群）")
    print("    jitter 后跨度 ≈ 半个退避窗口，请求被摊平")


async def main():
    await q1_loss()
    await q2_which_errors()
    await q3_naive_retry()
    await q4_backoff()

    await ka.config.load_kube_config()
    async with ApiClient() as api:
        try:
            await CoreV1Api(api).delete_namespace(name=NS)
            print(f"\n已清理 ns {NS}")
        except Exception as e:
            print(f"清理: {type(e).__name__}")


asyncio.run(main())
