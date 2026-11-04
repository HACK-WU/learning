"""M4：存活探针 vs 就绪探针——用错会怎样？

一个关键差异：
  · liveness 失败 → 容器被重启（进程没了）
  · readiness 失败 → 只是从负载均衡里摘掉（进程还活着）

造一个场景：3 个实例共享 1 个下游。下游变慢后，
  组 A：两个探针都检查"下游是否健康"（常见但致命的写法）
  组 B：liveness 只看自己活着，readiness 才看下游

纯标准库模拟，不用 k8s：用"进程被重启"= 实例状态重置 + 冷启动耗时 来表示。
"""
import threading
import time

DOWNSTREAM_DOWN = threading.Event()   # 下游是否处于故障中

COLD_START_MS = 1500                   # 冷启动代价：加载配置、建连接、预热缓存


class Instance:
    def __init__(self, sid, liveness_checks_downstream):
        self.sid = sid
        self.liveness_checks_downstream = liveness_checks_downstream
        self.alive = True
        self.ready = True
        self.restarts = 0
        self.uptime_serve_ms = 0.0      # 累计"能干活但不干活"的时间（重启+冷启动）
        self.lock = threading.Lock()

    # ---- 两个探针 ----
    def liveness(self):
        if self.liveness_checks_downstream and DOWNSTREAM_DOWN.is_set():
            return False                # ← 致命：把"依赖挂了"当成"我死了"
        return self.alive

    def readiness(self):
        if DOWNSTREAM_DOWN.is_set():
            return False                # ← 正确：依赖不可用，先别给我派活
        return self.alive

    def restart(self):
        with self.lock:
            self.restarts += 1
            self.uptime_serve_ms += COLD_START_MS   # 冷启动期间不能服务
            self.ready = False


class Cluster:
    def __init__(self, n, liveness_checks_downstream):
        self.nodes = [Instance(f"pod-{i+1}", liveness_checks_downstream) for i in range(n)]

    def tick(self, seconds, period=0.2):
        """模拟 kubelet 周期性探针 + 调度器按 readiness 选实例。"""
        t = 0.0
        while t < seconds:
            time.sleep(period)
            t += period
            for n in self.nodes:
                if not n.liveness():
                    n.restart()                     # 存活探针失败 → 重启
                n.ready = n.readiness() and not (n.uptime_serve_ms > 0 and n._cold)

    def summary(self):
        return {
            "restarts": sum(n.restarts for n in self.nodes),
            "cold_ms": sum(n.uptime_serve_ms for n in self.nodes),
        }


def run_group(label, liveness_checks_downstream, n=3, seconds=3.0):
    """简化版：直接按探针语义推演，不 sleep，纯确定性。"""
    nodes = [Instance(f"pod-{i+1}", liveness_checks_downstream) for i in range(n)]
    period = 0.2
    t = 0.0
    timeline = []
    while t < seconds - 1e-9:
        t = round(t + period, 2)
        for nd in nodes:
            live = nd.liveness()
            ready = nd.readiness()
            if not live:
                nd.restarts += 1
                nd.uptime_serve_ms += COLD_START_MS
                timeline.append((t, nd.sid, "被重启"))
                # 重启期间进程不在，下一轮探针会重新判定
            else:
                nd.ready = ready

    alive_ready = sum(1 for nd in nodes if not (liveness_checks_downstream and DOWNSTREAM_DOWN.is_set()))
    print(f"\n【{label}】3 个实例，下游故障持续 {seconds:.1f}s，探针周期 {period}s")
    print(f"  重启次数合计      : {sum(nd.restarts for nd in nodes)}")
    print(f"  冷启动损失        : {sum(nd.uptime_serve_ms for nd in nodes) / 1000:.1f} 秒·实例")
    print(f"  下游恢复时刻可用实例: {alive_ready} / {n}")
    if timeline:
        print(f"  重启事件（前 6 条）:")
        for t_, sid, what in timeline[:6]:
            print(f"    t={t_:.2f}s  {sid}  {what}")
        if len(timeline) > 6:
            print(f"    ... 共 {len(timeline)} 条")


print("=" * 74)
print("M4：存活探针检查依赖 = 把'依赖故障'升级成'集群全体重启'")
print("=" * 74)

DOWNSTREAM_DOWN.set()

run_group("组 A：liveness 也检查下游（常见错法）", liveness_checks_downstream=True)
run_group("组 B：liveness 只看自己，readiness 才看下游（正确）", liveness_checks_downstream=False)

DOWNSTREAM_DOWN.clear()
print("""
判读：
  · 组 A 每个探针周期都在重启：下游一直坏，liveness 就一直失败，容器被反复拉起，
    又因为冷启动期间也过不了 liveness，形成重启风暴。下游恢复后集群还得再花一个冷启动周期
  · 组 B 一次重启都没有：readiness 失败只是"摘流"，进程安安静静等着，
    下游一恢复立刻就能接流量
  · 核心区别不是"哪个探针更严格"，而是后果不同：
      liveness 失败 = 杀掉进程，代价不可逆
      readiness 失败 = 暂时不派活，代价可逆
    所以只有"这个进程自己不可救药"才该动 liveness；"依赖暂时不可用"只能动 readiness
""")
