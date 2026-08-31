"""
库存扣减：非幂等任务 —— 必须带 fencing token，且由「资源层」校验
对应知识点：阶段2 课6（fencing / Kleppmann）、阶段4 课12（锁服务只发号，资源层才是锁）

★★★ 本课最重要的一句：
    "The lock service is not the lock; the resource's rejection of stale tokens is the lock."
    锁服务的职责是「发一个单调的号」，真正的互斥由「资源层拒绝更旧的号」实现。

本文件演示两件事：
  1) 正确版：token 传给资源层，资源层拒绝旧 token → 即使进程暂停也不会写坏
  2) 错误版（对照）：不传 token 直接写 → 进程暂停后「自认有锁」继续写 → 超卖
"""
import time
import threading
from kazoo.client import KazooClient
from kazoo.recipe.lock import Lock

ZK_HOSTS = "127.0.0.1:2181"
STOCK_KEY = "sku-1001"


# ===========================================================================
# 模拟「资源层」：一个支持条件更新的存储（演示用内存字典代替 MySQL）
# 真实生产里对应：
#   UPDATE stock SET num = num - 1, version = ?
#   WHERE sku = ? AND ? >= last_seen_token      ← 带 token 的条件更新
# ===========================================================================
class StockStore:
    """
    ★ 关键设计：资源层自己记住「见过的最大 token」，拒绝更旧者。
      这就是 fencing —— 它不依赖客户端是否"以为"自己持有锁。
    """

    def __init__(self):
        self.stock = {STOCK_KEY: 10}          # 初始库存 10
        self.highest_token = {}               # sku -> 见过的最大 token
        self.lock = threading.Lock()

    def deduct(self, sku: str, token: int, amount: int = 1) -> bool:
        """
        带 fencing token 的扣减。
        :param token: 锁服务发的单调 token（ZK 用 czxid / etcd 用 revision）
        :return: True=扣减成功, False=被拒绝（token 过期，说明你已不持有锁）
        """
        with self.lock:
            last = self.highest_token.get(sku, -1)
            if token < last:
                # ★★★ 这就是 fencing：资源层拒绝旧 token，哪怕对方"以为"自己有锁
                print(f"   🚫 拒绝写入：token={token} < 已见最大 {last}（你的锁已过期）")
                return False
            if self.stock[sku] < amount:
                print(f"   ⚠️ 库存不足：剩余 {self.stock[sku]}")
                return False

            self.stock[sku] -= amount
            self.highest_token[sku] = token
            print(f"   ✅ 扣减成功：token={token}，剩余库存 {self.stock[sku]}")
            return True


# ===========================================================================
# 正确版：从锁里取 token，传给资源层
# ===========================================================================
def deduct_stock_correct(zk, store: StockStore, sku: str, simulate_pause=False):
    """
    正确做法。
    ★ 核心：token 从锁节点来（ZK 的 czxid 是单调递增的 zxid），
      每次写都带上，由资源层裁决 —— 而不是由"我是否持有锁"这个主观判断裁决。
    """
    lock = Lock(zk, f"/scheduler/locks/stock-{sku}")
    with lock:
        # 从「自己」这个锁节点取 czxid（创建该节点的事务 ID，全局单调递增）
        # ★ ZK 用 zxid/czxid 做 fencing token；etcd 用 revision/mod_revision
        # ★ 关键：必须取自己那个顺序节点的 czxid，不能取 min(children)（那可能是别人的）
        #   kazoo 的 Lock 内部会创建一个形如 /path/lock-000000000x 的临时顺序节点
        node_path = None
        for child in zk.get_children(f"/scheduler/locks"):
            if child.startswith("stock-"):
                # 找到属于当前锁的、且由本会话创建的节点：
                # 用 stat 对比——临时节点的 ephemeralOwner 是本会话 ID
                child_path = f"/scheduler/locks/{child}"
                data, stat = zk.get(child_path)
                if stat.ephemeralOwner == zk.client_id[0]:   # 本会话创建的临时节点
                    node_path = child_path
                    token = stat.czxid                        # ★ 单调 token
                    break
        if node_path is None:
            token = int(time.time() * 1000)         # 兜底（演示用，生产不该走到）
            print("   ⚠️ 未定位到自己的锁节点，token 用兜底值（仅演示）")
        else:
            print(f"   持有锁（{node_path}），token={token}")

        if simulate_pause:
            # 模拟：进程 GC 暂停 / 网络分区 —— 租约早已过期，别人已拿到锁
            print("   💤 模拟进程暂停（GC STW / 网络分区）… 期间租约已过期，别人已拿到锁")
            time.sleep(3)

        # ★ 关键：把 token 传给资源层，由它裁决。不是自己决定"我能不能写"
        return store.deduct(sku, token)


# ===========================================================================
# 错误版（对照）：不传 token，裸写 —— 反例 2 的可运行版本
# ===========================================================================
def deduct_stock_bad(zk, store_bad: StockStore, sku: str, simulate_pause=False):
    """
    ❌ 错误做法：以为"持有锁 = 安全"，不传 token 直接写。
    happy path 完全正常，只有遇到「进程暂停 + 租约过期」才会写坏数据。
    """
    lock = Lock(zk, f"/scheduler/locks/stock-{sku}")
    with lock:
        print("   持有锁（不取 token）")
        if simulate_pause:
            print("   💤 模拟进程暂停… 租约已过期，别人已拿到锁并改了库存")
            time.sleep(3)
        # ❌ 裸写：没有任何屏障能挡住"我醒了但我已不持有锁"
        with store_bad.lock:
            if store_bad.stock[sku] > 0:
                store_bad.stock[sku] -= 1
                print(f"   ⚠️ 裸写成功，剩余库存 {store_bad.stock[sku]}（但可能是超卖！）")
                return True
        return False


# ===========================================================================
# 演示：两种情况对照
# ===========================================================================
def demo():
    zk = KazooClient(hosts=ZK_HOSTS, timeout=10.0)
    zk.start()
    zk.ensure_path("/scheduler/locks")

    print("=" * 60)
    print("【A】正确版：token 落资源层（fencing 生效）")
    print("=" * 60)
    store = StockStore()
    # 第一次：正常扣减
    deduct_stock_correct(zk, store, STOCK_KEY, simulate_pause=False)
    # 第二次：模拟暂停后自认有锁 —— 资源层用 token 挡住
    print("\n-- 模拟『进程暂停→租约过期→自认有锁继续写』--")
    # 先让"别人"拿到更新的锁并写入（token 更大）
    lock2 = Lock(zk, f"/scheduler/locks/stock-{STOCK_KEY}")
    print("   （另一个节点已取得新锁并写入，占用了更大的 token）")
    store.highest_token[STOCK_KEY] = 999999   # 模拟：别人已用大 token 写过
    deduct_stock_correct(zk, store, STOCK_KEY, simulate_pause=True)
    print(f"   → 最终库存 {store.stock[STOCK_KEY]}（未被旧持有者写坏）✅")

    print("\n" + "=" * 60)
    print("【B】错误版：不传 token 裸写（fencing 缺失）")
    print("=" * 60)
    store_bad = StockStore()
    deduct_stock_bad(zk, store_bad, STOCK_KEY, simulate_pause=False)
    print("\n-- 同样模拟暂停 --")
    deduct_stock_bad(zk, store_bad, STOCK_KEY, simulate_pause=True)
    print(f"   → 最终库存 {store_bad.stock[STOCK_KEY]}（旧持有者的写入被接受了 ⚠️ 超卖风险）")

    print("\n" + "=" * 60)
    print("💡 结论：锁服务只负责『发一个单调的号』；")
    print("        真正的互斥 = 资源层拒绝更旧的号。")
    print("        若资源层不支持条件写（如不可改的第三方 API），换任何锁服务都无效（课12 案3）。")
    print("=" * 60)

    zk.stop()
    zk.close()


if __name__ == "__main__":
    demo()
