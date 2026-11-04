"""M2：两阶段提交（2PC）的代价 —— 阻塞窗口有多长

用一个真的 2PC 协调者 + 3 个"资源管理器"进程内模拟，
参与者 prepare 后真的加锁（互斥量 + 行级占用），
协调者在 prepare 之后崩溃，测量：
  R1 正常路径：2 轮往返、多少消息
  R2 协调者在 prepare 后崩溃：参与者阻塞多久、锁被占多久
  R3 超时兜底：参与者自己 abort 会怎样（一致性风险）
  R4 参与者多的时候，prepare 窗口随人数线性变长

纯标准库，python3 直接跑。约 12 秒。
"""
import itertools
import statistics
import threading
import time

LOCK = threading.Lock()


# ------------------------------------------------------------ 消息计数器
class Wire:
    def __init__(self):
        self.count = 0
        self.lock = threading.Lock()

    def send(self):
        with self.lock:
            self.count += 1

    def reset(self):
        with self.lock:
            self.count = 0


WIRE = Wire()


# ------------------------------------------------------------ 资源管理器
class ResourceManager:
    """一个参与者：prepare 后持有排他锁，直到 commit/abort。"""

    def __init__(self, name, prepare_ms=0):
        self.name = name
        self.prepare_ms = prepare_ms
        self.mutex = threading.Lock()
        self.state = "idle"
        self.prepared_at = None
        self.lock_held_ms = 0.0

    def prepare(self):
        # 真实语义：拿锁 → 写 redo/undo → 回 VOTE-COMMIT
        self.locked_at = time.monotonic()
        acquired = self.mutex.acquire(timeout=2.0)
        if not acquired:
            return "VOTE-ABORT", 0.0
        time.sleep(self.prepare_ms / 1000.0)
        self.state = "prepared"
        self.prepared_at = time.monotonic()
        WIRE.send()                      # 回票
        return "VOTE-COMMIT", (self.prepared_at - self.locked_at) * 1000

    def _finish(self, state):
        now = time.monotonic()
        self.state = state
        # 总持锁时间：从拿到锁到真正释放
        self.lock_held_ms = (now - self.locked_at) * 1000 if self.locked_at else 0.0
        # 不确定窗口：已经 prepare 完成、但还不知道该 commit 还是 abort
        self.uncertain_ms = (now - self.prepared_at) * 1000 if self.prepared_at else 0.0
        try:
            self.mutex.release()
        except RuntimeError:
            pass

    def commit(self):
        self._finish("committed")
        WIRE.send()

    def abort(self):
        self._finish("aborted")
        WIRE.send()

    def is_locked(self):
        # try acquire 探测：拿不到就是被别人占着
        got = self.mutex.acquire(blocking=False)
        if got:
            self.mutex.release()
            return False
        return True

    def force_abort_timeout(self):
        """模拟"参与者等不及自己回滚"——这就是超时兜底。"""
        self._finish("aborted-by-timeout")


# ------------------------------------------------------------ 协调者
class Coordinator:
    def __init__(self, rms, prepare_ms=30, parallel_prepare=False):
        self.rms = rms
        self.prepare_ms = prepare_ms
        self.parallel_prepare = parallel_prepare

    def _prepare_parallel(self):
        votes = [None] * len(self.rms)

        def worker(i, rm):
            WIRE.send()
            votes[i] = rm.prepare()[0]

        threads = [threading.Thread(target=worker, args=(i, rm))
                   for i, rm in enumerate(self.rms)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()
        return votes

    def run(self, crash_after_prepare=False, crash_hold_s=0.0, verbose=True):
        WIRE.reset()
        t0 = time.monotonic()
        if self.parallel_prepare:
            votes = self._prepare_parallel()
        else:
            votes = []
            for rm in self.rms:
                WIRE.send()                          # PREPARE 请求
                v, ms = rm.prepare()
                votes.append(v)

        prepare_done = time.monotonic()
        if crash_after_prepare:
            if verbose:
                print(f"  ⚠️  协调者在收齐投票后崩溃（已持有 {len(self.rms)} 把锁）")
                print(f"      崩溃时刻：{prepare_done - t0:.3f}s，"
                      f"消息数 {WIRE.count}")
            # 崩溃期间：没有人发决定，参与者一直阻塞
            time.sleep(crash_hold_s)
            blocked_ms = (time.monotonic() - prepare_done) * 1000
            if verbose:
                print(f"      阻塞 {crash_hold_s:.2f}s 后协调者被人工拉起")
            # 恢复后读日志决定 commit
            for rm in self.rms:
                WIRE.send()                          # COMMIT 决定
                rm.commit()
            total = (time.monotonic() - t0) * 1000
            if verbose:
                print(f"      事务总耗时 {total:.1f}ms，其中纯阻塞 {blocked_ms:.1f}ms")
                print(f"      总消息数 {WIRE.count}")
            return {
                "blocked_ms": blocked_ms,
                "total_ms": total,
                "messages": WIRE.count,
                "locks_held": [rm.lock_held_ms for rm in self.rms],
                "uncertain": [rm.uncertain_ms for rm in self.rms],
            }

        if all(v == "VOTE-COMMIT" for v in votes):
            for rm in self.rms:
                WIRE.send()                          # COMMIT
                rm.commit()
            decision = "GLOBAL-COMMIT"
        else:
            for rm in self.rms:
                WIRE.send()                          # ABORT
                rm.abort()
            decision = "GLOBAL-ABORT"

        total = (time.monotonic() - t0) * 1000
        if verbose:
            print(f"  决定 {decision}｜总耗时 {total:.1f}ms｜消息数 {WIRE.count}")
            print(f"  总持锁时间（加锁→释放）"
                  f" {[round(rm.lock_held_ms, 1) for rm in self.rms]} ms")
            print(f"  不确定窗口（prepare 完成→收到决定）"
                  f" {[round(rm.uncertain_ms, 1) for rm in self.rms]} ms")
        return {
            "blocked_ms": 0.0,
            "total_ms": total,
            "messages": WIRE.count,
            "locks_held": [rm.lock_held_ms for rm in self.rms],
            "uncertain": [rm.uncertain_ms for rm in self.rms],
        }


def line(t):
    print(f"\n{'-' * 72}\n{t}\n{'-' * 72}")


# ------------------------------------------------------------ 场景
def r1_normal():
    line("R1 正常路径：3 个参与者，各自 prepare 30ms")
    print("  先看串行发 PREPARE（很多人第一版就是这么写的）：")
    rms = [ResourceManager(f"rm{i}", prepare_ms=30) for i in range(1, 4)]
    co = Coordinator(rms, parallel_prepare=False)
    r = co.run()
    print(f"  → 消息数 = 2n = {r['messages']}（PREPARE 一轮 + COMMIT 一轮）")
    print(f"  ⚠️  rm1 总持锁 {r['locks_held'][0]:.1f}ms ≈ 3 × 30ms：")
    print(f"      它 prepare 完就一直等着，后面的参与者还在排队")

    print("\n  再看并行发 PREPARE（真实 2PC 实现的做法）：")
    rms2 = [ResourceManager(f"rm{i}", prepare_ms=30) for i in range(1, 4)]
    co2 = Coordinator(rms2, parallel_prepare=True)
    r2 = co2.run()
    print(f"  → 消息数同样是 {r2['messages']}，一个字节都没省")
    print(f"  → 总耗时 {r['total_ms']:.1f}ms → {r2['total_ms']:.1f}ms"
          f"（{r['total_ms'] / r2['total_ms']:.1f}× 差距）")
    print(f"  → 串行时 rm1 的不确定窗口是 {r['uncertain'][0]:.1f}ms"
          f"（它在等别人 prepare）")
    print(f"     并行时是 {r2['uncertain'][0]:.1f}ms（大家同时到达）")
    print("  → 并行能压掉「排队等别人」这段，压不掉「prepare 完等决定」这段——")
    print("    后者才是 2PC 阻塞风险的本体，长度由协调者决定，不由参与者决定")


def r2_blocking():
    line("R2 协调者在 prepare 之后崩溃：参与者阻塞多久、锁占多久")
    # 先取同口径的正常基线（并行 prepare，与真实实现一致）
    base_rms = [ResourceManager(f"rm{i}", prepare_ms=30) for i in range(1, 4)]
    base = Coordinator(base_rms, parallel_prepare=True).run(verbose=False)
    base_unc = max(base["uncertain"])
    print(f"  基线（同一套参与者、同一 prepare 耗时，不崩溃）：")
    print(f"    总持锁 {max(base['locks_held']):.1f}ms，"
          f"不确定窗口 {base_unc:.1f}ms")

    rms = [ResourceManager(f"rm{i}", prepare_ms=30) for i in range(1, 4)]
    co = Coordinator(rms, parallel_prepare=True)
    hold = 2.0
    r = co.run(crash_after_prepare=True, crash_hold_s=hold)
    print(f"  → 阻塞 {r['blocked_ms']:.1f}ms 完全是白等：数据已写好、锁已拿着，"
          f"但没人告诉它该 commit 还是 abort")
    print(f"  → 总持锁 {max(r['locks_held']):.1f}ms，其中不确定窗口 "
          f"{max(r['uncertain']):.1f}ms")
    print(f"     同一套代码不崩溃时这个窗口只有 {base_unc:.1f}ms"
          f"（差 {max(r['uncertain']) - base_unc:.0f}ms）")
    print("  → 差的这部分不是算力，是「没人告诉它该怎么办」的纯等待")
    print("  → 这就是 2PC 被称为「阻塞协议」的确切位置：不是慢，是可能永远不结束")


def r3_timeout():
    line("R3 超时兜底：参与者等不及自己回滚，会怎样")
    rms = [ResourceManager(f"rm{i}", prepare_ms=30) for i in range(1, 4)]
    co = Coordinator(rms)

    # 手动走一遍，模拟协调者崩溃后参与者各自超时
    WIRE.reset()
    for rm in rms:
        WIRE.send()
        rm.prepare()
    print(f"  3 个参与者都已 VOTE-COMMIT，锁已持有")

    # 关键：假设协调者其实已经决定了 COMMIT 并写进日志，
    # 但只发出了 1 个 COMMIT 就重启了
    rms[0].commit()
    print(f"  rm1 已收到 COMMIT 并提交（这是既成事实）")

    # rm2 / rm3 超时，自己 abort
    time.sleep(0.3)
    for rm in rms[1:]:
        rm.force_abort_timeout()
        print(f"  {rm.name} 超时 300ms，自行 abort")

    states = [rm.state for rm in rms]
    print(f"  最终状态：{states}")
    print("  → 同一个全局事务，rm1 提交了、rm2/rm3 回滚了")
    print("  → 超时兜底换来了「不阻塞」，代价是「可能不一致」")
    print("  → 这就是为什么真实系统宁可阻塞等人工，也不敢让参与者自己猜")


def r4_scaling():
    line("R4 参与者越多，阻塞窗口和锁数量怎么变")
    print(f"  {'参与者数':<9}{'串行总耗时':<13}{'并行总耗时':<13}{'消息数':<9}{'被卡的锁'}")
    for n in (2, 4, 8, 16):
        rms = [ResourceManager(f"rm{i}", prepare_ms=5) for i in range(1, n + 1)]
        r_serial = Coordinator(rms, parallel_prepare=False).run(verbose=False)

        rms2 = [ResourceManager(f"rm{i}", prepare_ms=5) for i in range(1, n + 1)]
        r_par = Coordinator(rms2, parallel_prepare=True).run(verbose=False)

        print(f"  {n:<9}{r_serial['total_ms']:<13.1f}{r_par['total_ms']:<13.1f}"
              f"{r_par['messages']:<9}{n}")
    print("  → 消息数 2n 线性增长；一旦协调者崩在 prepare 之后，")
    print("    这 n 把锁全部卡住，n 越大，被牵连的业务越多")
    print("  → 并行能把耗时压到「最慢的那个」，但压不掉锁数量：")
    print("    崩溃时被卡住的永远是全部 n 把锁")


def main():
    print("=" * 72)
    print("M2：两阶段提交的代价（真实加锁的 2PC 模拟）")
    print("=" * 72)
    r1_normal()
    r2_blocking()
    r3_timeout()
    r4_scaling()


if __name__ == "__main__":
    main()
