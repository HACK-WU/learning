"""验证 5b：修正测法后的参数校验

上一轮测法错误：onstarted_leading 传 None，触发的是
"callback cannot be None"，把 jitter 校验掩盖了。
本轮传真实协程函数，单独隔离出时间参数的校验。
"""
import sys

sys.path.insert(0, "/mnt/d/projects/learning/k8s/子教程/Python客户端专项/assets/lesson06-async")

import asyncio

from kubernetes_asyncio.leaderelection.electionconfig import Config
from kubernetes_asyncio.leaderelection.resourcelock.leaselock import LeaseLock

NS = "py-lesson06-le"


async def noop():
    pass


async def main():
    print("=" * 70)
    print("参数校验（传真实回调，隔离时间参数）")
    print("=" * 70)

    # 不需要真连集群：LeaseLock 构造不发起请求
    import kubernetes_asyncio as ka
    await ka.config.load_kube_config()
    from kubernetes_asyncio.client import ApiClient
    async with ApiClient() as api:
        lock = LeaseLock("demo", NS, "id-1", api)

        cases = [
            ("lease=10 renew=5  retry=2", 10, 5, 2, True, "基准合法"),
            ("lease=10 renew=2  retry=2", 10, 2, 2, False, "renew 2 < retry*1.2=2.4"),
            ("lease=10 renew=2.5 retry=2", 10, 2.5, 2, True, "renew 2.5 > 2.4 边界过"),
            ("lease=10 renew=2.4 retry=2", 10, 2.4, 2, False, "renew 2.4 = 2.4 不过（严格大于）"),
            ("lease=5  renew=5  retry=2", 5, 5, 2, False, "lease == renew"),
            ("lease=6  renew=5  retry=2", 6, 5, 2, True, "lease > renew 最小"),
            ("lease=10 renew=5  retry=1", 10, 5, 1, True, "retry=1 边界"),
            ("lease=10 renew=5  retry=0", 10, 5, 0, False, "retry<1"),
        ]
        all_ok = True
        for label, ld, rd, rp, should_ok, why in cases:
            try:
                Config(lock, ld, rd, rp, noop, noop)
                got, err = True, ""
            except ValueError as e:
                got, err = False, str(e)
            ok = (got == should_ok)
            all_ok &= ok
            print(f"  [{'OK ' if ok else '!! '}] {label:<28} 构造={str(got):<5} {why}")
            if err:
                print(f"          err: {err[:70]}")

        print()
        if all_ok:
            print("  ✓ 全部符合预期")
        else:
            print("  !! 有不符合预期的用例")

        print()
        print("  实测结论:")
        print("    jitter_factor = 1.2，校验是 renew_deadline > retry_period * 1.2")
        print("    ⚠️ 注意是**严格大于**：renew=2.4, retry=2 时 2.4 > 2.4 为假 -> 抛 ValueError")
        print("    client-go 官方建议: lease=15, renew=10, retry=2")
        print("    本机最小可用: lease=6, renew=5, retry=2")


asyncio.run(main())
