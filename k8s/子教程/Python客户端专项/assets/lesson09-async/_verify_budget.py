"""核验：预算 0.5 时"耗尽 50 次"= 全部重试被拒？

疑点：B3 中 n=50、ratio=0.5，预算耗尽 50 次（等于全部调用数），
放大恰好 1.50x。若所有重试都被拒，则预算**完全没发挥作用**
（不是"限制放大"，而是"干脆不许重试"），这是个设计缺陷而非特性。

按铁律：数字太整齐（恰好 1.50x、恰好 50 次）先怀疑测法/实现。

根因猜测：B3 里每个调用都新建独立 Flaky，且全部**同时**发起。
第一批 50 个首轮请求先执行完 → first_round=50 → 允许重试 25 次。
但 asyncio.gather 让 50 个协程交错，若首轮尚未全部 count_first，
先到的协程拿到的 first_round 基数偏小 → 早期重试被拒。

本脚本验证：
 V1. 预算是否真的放行了部分重试（还是全拒）
 V2. 首轮计数与重试的时序关系
 V3. 与"不用预算"对比，成功数是否真的更好
"""
import asyncio
import sys

from retry_middleware import (ApiException, RetryPolicy, RetryStats, _Budget,
                              retry_k8s)


class Flaky:
    def __init__(self, fail_times, status=503):
        self.calls = 0
        self.fail_times = fail_times        # 前 N 次失败，之后成功

    async def __call__(self):
        self.calls += 1
        if self.calls <= self.fail_times:
            raise ApiException(self.status, "injected")
        return "ok"


async def v1_budget_allows_some():
    print("=== V1. 预算是否放行了部分重试 ===")
    n = 20
    budget = _Budget(ratio=1.0)
    st = RetryStats()
    srvs = []
    coros = []
    for _ in range(n):
        s = Flaky(fail_times=1)             # 只失败 1 次，重试即成功
        srvs.append(s)
        coros.append(retry_k8s(
            s, policy=RetryPolicy(max_attempts=3),
            stats=st, budget=budget))
    res = await asyncio.gather(*coros, return_exceptions=True)
    ok = sum(1 for r in res if r == "ok")
    print(f"  ratio=1.0, 每调用失败1次: 成功 {ok}/{n}")
    print(f"  retry 计数 retries={st.retries}, "
          f"budget_exhausted={st.budget_exhausted}")
    if ok < n:
        print("  ⚠️ 预算充足却仍有失败 → 实现有问题")
    else:
        print("  ✓ 预算充足时全部重试成功")


async def v2_ratio_sweep():
    print()
    print("=== V2. 不同 ratio 下的实际放大与成功率 ===")
    n = 40
    print(f"  {'ratio':>6} {'成功':>6} {'放大':>7} {'重试':>6} {'耗尽':>6}")
    for ratio in (0.0, 0.25, 0.5, 1.0, 2.0):
        budget = _Budget(ratio=ratio) if ratio > 0 else None
        st = RetryStats()
        coros = []
        for _ in range(n):
            s = Flaky(fail_times=1)
            coros.append(retry_k8s(
                s, policy=RetryPolicy(max_attempts=4),
                stats=st, budget=budget))
        res = await asyncio.gather(*coros, return_exceptions=True)
        ok = sum(1 for r in res if r == "ok")
        amp = st.attempts / n
        print(f"  {ratio:>6} {ok:>4}/{n} {amp:>6.2f}x "
              f"{st.retries:>6} {st.budget_exhausted:>6}")


async def v3_timing_effect():
    print()
    print("=== V3. 首轮计数时序的影响 ===")
    n = 30
    budget = _Budget(ratio=0.5)
    st = RetryStats()
    coros = [retry_k8s(Flaky(fail_times=1),
                       policy=RetryPolicy(max_attempts=3),
                       stats=st, budget=budget) for _ in range(n)]
    res = await asyncio.gather(*coros, return_exceptions=True)
    ok = sum(1 for r in res if r == "ok")
    print(f"  全部同时发起: 成功 {ok}/{n}, first_round={budget.first_round}, "
          f"retries_used={budget.retries_used}")
    print(f"  理论允许重试 = {n * 0.5:.0f}")
    print(f"  实际重试     = {budget.retries_used}")
    if budget.retries_used == 0:
        print("  ⚠️ 实际重试为 0 → 所有协程在首轮计数完成前就已重试并被拒")
        print("     这不是'限流'，而是**预算基数未建立时的饥饿**")

    print()
    print("  对照：先完成首轮计数再重试（预热）")
    budget2 = _Budget(ratio=0.5)
    st2 = RetryStats()
    # 先灌满基数
    for _ in range(n):
        await budget2.count_first()
    coros2 = [retry_k8s(Flaky(fail_times=1),
                        policy=RetryPolicy(max_attempts=3),
                        stats=st2, budget=budget2) for _ in range(n)]
    res2 = await asyncio.gather(*coros2, return_exceptions=True)
    ok2 = sum(1 for r in res2 if r == "ok")
    print(f"  预热后: 成功 {ok2}/{n}, retries_used={budget2.retries_used}")
    print(f"  → 差异说明：{'时序饥饿确实存在' if ok2 > ok else '无明显时序饥饿'}")


async def main():
    await v1_budget_allows_some()
    await v2_ratio_sweep()
    await v3_timing_effect()


if __name__ == "__main__":
    asyncio.run(main())
