"""验证 2：两种工作队列语义对比

课 6 同步版是「事件驱动 → 立即调谐」，没有去重概念。
异步版引入工作队列后，去重语义决定了正确性。

AsyncWorkQueue (v1 朴素)：add 时若在 in-flight 就丢弃
  -> 处理期间的变更被永久漏掉
AsyncWorkQueueFixed (v2)：add 时若在 processing 则标记 dirty，done() 后重入队
  -> 对齐 client-go，不丢变更

实测：调谐慢（delay=1.0s），期间连续改同一对象，看会不会漏掉最后一次
"""
import asyncio
import sys
import time

sys.path.insert(0, "/mnt/d/projects/learning/k8s/子教程/Python客户端专项/assets/lesson06-async")

import kubernetes_asyncio as ka
from kubernetes_asyncio.client import ApiClient, CoreV1Api

from async_controller import AsyncWorkQueue, AsyncWorkQueueFixed

NS = "py-lesson06-queue"


async def demo_queue_semantics():
    print("=" * 70)
    print("纯队列语义对比（不涉及 k8s，纯逻辑）")
    print("=" * 70)

    for cls, label in ((AsyncWorkQueue, "v1 朴素"), (AsyncWorkQueueFixed, "v2 Fixed")):
        q = cls()
        print(f"\n  --- {label} ---")

        q.add("A")                    # 入队
        n1 = await asyncio.wait_for(q.get(), timeout=0.5)
        print(f"    取出: {n1}")

        # 处理期间，A 又变了 2 次
        r1 = q.add("A")
        r2 = q.add("A")
        print(f"    处理期间再 add('A') x2 -> 返回 {r1}, {r2}")

        requeued = q.done("A")
        print(f"    done('A') -> 是否重新入队: {requeued}")

        try:
            n2 = await asyncio.wait_for(q.get(), timeout=0.5)
            print(f"    再次取出: {n2}   <- {'✓ 变更没丢' if n2 == 'A' else '?'}")
        except asyncio.TimeoutError:
            print(f"    再次取出: (队列空)  <- ✗ 变更被永久漏掉！")


async def demo_end_to_end():
    print()
    print("=" * 70)
    print("端到端：调谐慢 + 期间连续变更，对比两种队列")
    print("=" * 70)

    await ka.config.load_kube_config()

    for cls, label in ((AsyncWorkQueue, "v1 朴素"), (AsyncWorkQueueFixed, "v2 Fixed")):
        print(f"\n  ########## {label} ##########")
        async with ApiClient() as api:
            v1 = CoreV1Api(api)
            try:
                await v1.create_namespace(body={"metadata": {"name": NS}})
            except Exception:
                pass

            q = cls()

            # 模拟：对象在调谐过程中又变了一次
            # 场景：X 缺 managed -> 调谐(delay 1s) -> 期间外部把 X 的 data.k 改成 k2
            #       -> 期望：调谐完后 X 仍应被再调谐一次（虽本例 no_op，但关键是"再看一眼"）
            await v1.create_namespaced_config_map(
                namespace=NS,
                body={"metadata": {"name": "x"}, "data": {"k": "v1"}})

            q.add("x")
            name = await asyncio.wait_for(q.get(), timeout=0.5)

            # 处理中：外部改了对象
            await v1.patch_namespaced_config_map(
                name="x", namespace=NS, body={"data": {"k": "v2"}})
            q.add("x")            # 变更到达
            q.add("x")            # 又变更

            # 处理完成
            requeued = q.done(name)

            print(f"    处理期间 add('x') x2")
            print(f"    done('x') -> 重入队: {requeued}")
            try:
                again = await asyncio.wait_for(q.get(), timeout=0.5)
                print(f"    -> 再次取出 '{again}'  ✓ 变更被保留")
            except asyncio.TimeoutError:
                print(f"    -> 队列空  ✗ 变更被丢弃")

            try:
                await v1.delete_namespace(name=NS)
                await asyncio.sleep(0.5)
            except Exception:
                pass
            # 等 ns 真删掉
            for _ in range(30):
                try:
                    await v1.read_namespace(name=NS)
                    await asyncio.sleep(0.3)
                except Exception:
                    break


async def main():
    await demo_queue_semantics()
    await demo_end_to_end()

    print()
    print("=" * 70)
    print("结论")
    print("=" * 70)
    print("  v1 朴素去重：add 时 in-flight -> 丢弃")
    print("     处理期间到达的变更会被**永久丢失**，控制器永远看不到")
    print("     这是最危险的 bug：不报错、不崩溃，只是状态静默落后")
    print()
    print("  v2 Fixed（client-go 语义）：add 时 processing -> 标记 dirty")
    print("     done() 后发现仍 dirty -> 重新入队")
    print("     -> 无论变更多频繁，最终至少再调谐一次（收敛保证）")
    print()
    print("  判据：写工作队列时问一句")
    print("    「对象正在被处理时又变了，这次变更会被看到吗？」")


asyncio.run(main())
