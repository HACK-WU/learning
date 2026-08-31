"""
分布式锁 + 主节点选举（正确版）
对应知识点：阶段2 课6（锁配方：只 watch 前驱，避免羊群）、课3（临时/顺序节点）、课5（watch 一次性）
依赖：pip install kazoo==2.11.0
"""
import threading
import time
import uuid
from kazoo.client import KazooClient
from kazoo.exceptions import NodeExistsError, NoNodeError
from kazoo.recipe.lock import Lock
from kazoo.recipe.election import Election

ZK_HOSTS = "127.0.0.1:2181"
LOCK_ROOT = "/scheduler/locks"        # 锁的根路径（持久节点）
ELECTION_PATH = "/scheduler/leader"   # 选主路径


# ---------------------------------------------------------------------------
# 1) 分布式锁：直接用 kazoo 的 Lock 配方
#    ★ 为什么用配方而不是手写：kazoo 的 Lock 内部已经是「排队 + 只 watch 前驱」
#      这正是课6 的锁配方、课8 的羊群效应反面对照。
#      手写版（大家都 watch 同一把锁）在竞争者变多时会引发 Watch 风暴。
# ---------------------------------------------------------------------------
def make_lock(zk, name):
    """
    创建一个互斥锁。
    注意：锁的「正确性」不在这个对象里 —— 真正的互斥由调用方把 token 传给资源层实现（见 stock_task.py）
    """
    zk.ensure_path(LOCK_ROOT)          # ensure_path 是幂等的，不存在才建（课3 持久节点）
    return Lock(zk, f"{LOCK_ROOT}/{name}")


# ---------------------------------------------------------------------------
# 2) 主节点选举：用 kazoo 的 Election 配方（内部基于最小序号临时节点）
#    ★ 原理：所有人创建临时顺序节点，序号最小者为主；次小者 watch 前驱（课6 选主配方）
#    ★ 用临时节点（ephemeral）：会话一断节点自动消失，天然实现「存活即持有」（课5）
# ---------------------------------------------------------------------------
def run_for_leader(zk, node_id, on_become_leader):
    """
    竞选 Leader。成为 Leader 后调用 on_become_leader()。
    非 Leader 的副本会阻塞在这里待命（这正是「待命副本」的正确行为）。
    """
    zk.ensure_path(ELECTION_PATH)
    election = Election(zk, ELECTION_PATH)

    print(f"[{node_id}] 参与竞选，等待成为 Leader…")
    # Election.run() 会阻塞：未当选时等待；当选后执行回调；回调返回后重新参与竞选
    election.run(on_become_leader, data=node_id.encode())


# ---------------------------------------------------------------------------
# 3) 幂等任务的轻量锁（对应「决策 2」的轻量档）
#    ★ 前提：任务必须幂等（重复执行结果一样）
#    ★ 这里仍用 ZK 锁做演示；生产上幂等任务可换成 Redis SET NX PX 省成本（见设计决策.md）
# ---------------------------------------------------------------------------
def idempotent_task(zk, node_id):
    """对账任务：重复执行只是多跑一次，属于「效率问题」"""
    lock = make_lock(zk, "reconcile")
    with lock:                                   # 临界区尽量短（课6：重活移出锁外）
        print(f"[{node_id}] 执行对账（幂等，重跑无害）")
        time.sleep(1)


def leader_loop(node_id):
    """Leader 的主循环：持续执行幂等任务，直到失去 Leadership"""
    zk = KazooClient(hosts=ZK_HOSTS, timeout=10.0)   # timeout 是连接超时，不是会话超时
    zk.start()
    print(f"[{node_id}] 已连接 ZK，会话超时 = {zk._session_timeout}ms")
    # ★ 注意：会话超时由服务端协商钳制，范围 [2×tickTime, 20×tickTime]（课5）
    #   默认 tickTime=2000 → 客户端请求的超时会被钳到 4s~40s

    try:
        run_for_leader(
            zk, node_id,
            on_become_leader=lambda: _leader_work(zk, node_id)
        )
    finally:
        zk.stop()
        zk.close()


def _leader_work(zk, node_id):
    """成为 Leader 后要做的事。返回后 Election 会让它重新排队竞选。"""
    print(f"[{node_id}] ⭐ 我是 Leader，开始执行调度")
    for i in range(10):                 # 演示：执行 10 轮后主动退位（便于观察交接）
        idempotent_task(zk, node_id)
        time.sleep(2)
    print(f"[{node_id}] 完成一轮，退出 Leadership")


# ---------------------------------------------------------------------------
# 4) 成员感知：Worker 用临时节点注册（对应知识点：课5 临时节点 + watch）
# ---------------------------------------------------------------------------
def register_worker(zk, node_id):
    """
    注册自己为存活 Worker。
    ★ 用 ephemeral（临时）节点：会话断开/过期，节点自动删除 → 别人能立刻感知（课5）
    """
    path = f"/scheduler/workers/{node_id}"
    zk.ensure_path("/scheduler/workers")
    # ephemeral=True 是关键：进程崩了节点也会消失，不会留下「僵尸 Worker」
    zk.create(path, node_id.encode(), ephemeral=True, makepath=True)
    print(f"[{node_id}] 已注册为 Worker（临时节点）")


def watch_workers(zk):
    """
    监听 Worker 列表变化。
    ★★★ 关键点：watch 是一次性的（课5）！
        每次回调后必须重新设置 watch，否则第二次变化就收不到了（见反例对照 反例3）
    """
    def _on_change(children):
        print(f"   ↳ Worker 列表变化，当前存活：{sorted(children)}")
        # 重新注册 watch —— kazoo 的 ChildrenWatch 装饰器会自动重注册，
        # 但如果你手写 get_children(watch=...)，必须自己再注册一次！

    zk.ensure_path("/scheduler/workers")
    zk.ChildrenWatch("/scheduler/workers")(_on_change)   # kazoo 自动重注册


# ---------------------------------------------------------------------------
# 入口
# ---------------------------------------------------------------------------
if __name__ == "__main__":
    import sys
    node_id = sys.argv[sys.argv.index("--node-id") + 1] if "--node-id" in sys.argv else f"worker-{uuid.uuid4().hex[:6]}"

    zk = KazooClient(hosts=ZK_HOSTS, timeout=10.0)
    zk.start()
    register_worker(zk, node_id)
    watch_workers(zk)

    try:
        run_for_leader(zk, node_id, on_become_leader=lambda: _leader_work(zk, node_id))
    except KeyboardInterrupt:
        print(f"\n[{node_id}] 退出")
    finally:
        zk.stop()
        zk.close()
