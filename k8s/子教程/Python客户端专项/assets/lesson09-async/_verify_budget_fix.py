"""验证修复：预算时序饥饿是否消除

修复前（_verify_budget.py 实测）：
  ratio=0.5, n=30 同时发起 → 成功 15/30（时序饥饿）
  预热对照组          → 成功 30/30

修复后预期：
  同时发起就应该与预热一致（额度按 total 固定，与时序无关）
"""
import asyncio
import sys

from retry_middleware import (ApiException, RetryPolicy, RetryStats, _Budget,
                              gather_with_retry, retry_k8s)

PASS = FAIL = 0


def check(label, cond, detail=""):
    global PASS, FAIL
    if cond:
        PASS += 1
        print(f"  ✓ {label} {detail}")
    else:
        FAIL += 1
        print(f"  ✗ {label} {detail}")


class Flaky:
    def __init__(self, fail_times=1, status=503):
        self.calls = 0
        self.fail_times = fail_times

    async def __call__(self):
        self.calls += 1
        if self.calls <= self.fail_times:
            raise ApiException(self.status, "injected")
        return "ok"


async def t_fixed_total():
    print("=== 修复点：total 固定额度 ===")
    n = 30
    budget = _Budget(ratio=0.5, total=n)
    st = RetryStats()
    coros = [retry_k8s(Flaky(fail_times=1),
                       policy=RetryPolicy(max_attempts=3),
                       stats=st, budget=budget) for _ in range(n)]
    res = await asyncio.gather(*coros, return_exceptions=True)
    ok = sum(1 for r in res if r == "ok")
    allowed = n * 0.5
    print(f"  同时发起: 成功 {ok}/{n}（理论上限 {int(allowed)}，"
          f"因每调用只需 1 次重试）")
    check("额度用满", budget.retries_used == int(allowed),
          f"used={budget.retries_used} / allowed={int(allowed)}")
    check("成功率 = 额度/总数", ok == int(allowed), f"{ok}")


async def t_gather_uses_total():
    print()
    print("=== gather_with_retry 自动传 total ===")
    n = 30
    calls = [(Flaky(fail_times=1), (), {}) for _ in range(n)]
    ok, st = await gather_with_retry(calls, policy=RetryPolicy(
        max_attempts=3, retry_budget=1.0))
    check("ratio=1.0 全部成功", len(ok) == n, f"{len(ok)}/{n}")

    ok2, st2 = await gather_with_retry(
        [(Flaky(fail_times=1), (), {}) for _ in range(n)],
        policy=RetryPolicy(max_attempts=3, retry_budget=0.5))
    print(f"  ratio=0.5: 成功 {len(ok2)}/{n}, 放大 {st2.attempts/n:.2f}x")
    check("ratio=0.5 成功约一半", abs(len(ok2) - n * 0.5) <= 1, f"{len(ok2)}")


async def t_no_regression():
    print()
    print("=== 回归：原有能力未破坏 ===")

    # 无预算时照常全重试
    calls = [(Flaky(fail_times=1), (), {}) for _ in range(20)]
    ok, st = await gather_with_retry(calls, policy=RetryPolicy(max_attempts=3))
    check("无预算全成功", len(ok) == 20, f"{len(ok)}/20")
    check("放大 2.00x", abs(st.attempts / 20 - 2.0) < 0.01,
          f"{st.attempts/20:.2f}x")

    # fatal 不重试
    n_calls = {"v": 0}

    async def fatal():
        n_calls["v"] += 1
        raise ApiException(404)

    st2 = RetryStats()
    try:
        await retry_k8s(fatal, policy=RetryPolicy(max_attempts=5), stats=st2)
    except ApiException:
        pass
    check("404 仍只调 1 次", n_calls["v"] == 1, f"{n_calls['v']}")


async def main():
    await t_fixed_total()
    await t_gather_uses_total()
    await t_no_regression()
    print()
    print(f"===== 通过 {PASS} / 失败 {FAIL} =====")
    return 1 if FAIL else 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
