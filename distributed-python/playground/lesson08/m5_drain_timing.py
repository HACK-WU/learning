"""M5：摘流与回流的时序——为什么"探针刚通过就放流量"是错的？

真实链路：实例重启 → 冷启动 → 探针开始通过 → 真正可服务，
这四步之间存在时间差。本脚本按真实参数把时间轴画出来，量化两个坑：

  坑 1：readiness 刚通过就立刻打满流量 → 实例被冷启动残留的慢请求压垮
  坑 2：滚动升级时没摘流就杀进程 → 在途请求被硬断

用确定性时间轴模拟（不用真起容器），参数取 Kubernetes 默认值量级。
"""
import json

# ---- 参数（贴近真实默认值）----
INIT_MS = 200                 # 进程起来到端口能连上
WARM_MS = 1800                # 预热：连池、缓存、JIT
PROBE_PERIOD_MS = 1000        # periodSeconds: 10 太多，这里用 1s 便于观察
PROBE_TIMEOUT_MS = 200
SUCCESS_THRESHOLD = 1         # successThreshold
FAILURE_THRESHOLD = 3         # failureThreshold
SIGTERM_GRACE_MS = 30000      # terminationGracePeriodSeconds

print("=" * 74)
print("M5：摘流/回流的时序坑")
print("=" * 74)
print(f"参数：启动 {INIT_MS}ms ｜ 预热 {WARM_MS}ms ｜ 探针周期 {PROBE_PERIOD_MS}ms "
      f"｜ 超时 {PROBE_TIMEOUT_MS}ms ｜ 优雅退出 {SIGTERM_GRACE_MS}ms")
print()

# ---- 场景 1：readiness 与"真正能服务"不是同一时刻 ----
print("场景 1：readiness 通过 ≠ 立刻能扛满流量")
print("-" * 74)
rows = []
for label, ready_at in [
    ("readiness 只 ping 端口（不看预热）", INIT_MS + PROBE_PERIOD_MS),
    ("readiness 校验预热完成", INIT_MS + WARM_MS + PROBE_PERIOD_MS),
]:
    rows.append((label, ready_at))
for label, ready_at in rows:
    print(f"  {label}")
    print(f"    最早开始接流量: t = {ready_at} ms")
    print(f"    真正扛得住满负载: t = {INIT_MS + WARM_MS} ms")
    gap = max(0, (INIT_MS + WARM_MS) - ready_at)
    if gap:
        print(f"    ⚠️ 危险窗口 {gap} ms：这段时间流量已经来了，但实例还没热起来")
    else:
        print(f"    ✅ 无危险窗口（探针比预热更保守）")
    print()

# ---- 场景 2：滚动升级，先杀进程还是先摘流 ----
print("场景 2：滚动升级时，摘流与 SIGTERM 的先后")
print("-" * 74)
inflight_ms = 300            # 在途请求最长 300ms
POD_DELETE_PROPAGATION_MS = 200   # endpoint 摘除传播到各节点 LB 的时间

orders = [
    ("先 SIGTERM，再摘 endpoint（常见错法）",
     [("收到 SIGTERM，进程开始退出", 0),
      ("endpoint 摘除传播完成", POD_DELETE_PROPAGATION_MS),
      ("在途请求最长耗时", inflight_ms)]),
    ("先摘 endpoint，等传播完成再 SIGTERM（正确）",
     [("endpoint 摘除传播完成", POD_DELETE_PROPAGATION_MS),
      ("收到 SIGTERM，进程开始退出", POD_DELETE_PROPAGATION_MS),
      ("在途请求最长耗时", inflight_ms)]),
]
for label, events in orders:
    print(f"  {label}")
    for what, t in events:
        print(f"    t={t:>4} ms  {what}")
    lose = max(0, POD_DELETE_PROPAGATION_MS - 0) if "先 SIGTERM" in label else 0
    if "先 SIGTERM" in label:
        print(f"    ⚠️ 从杀进程到摘流生效有 {POD_DELETE_PROPAGATION_MS} ms 的窗口，"
              f"在途 {inflight_ms} ms 的请求会被硬断")
        print(f"       而且这 {POD_DELETE_PROPAGATION_MS} ms 里 LB 还在把新请求发给它")
    else:
        print(f"    ✅ 摘流生效后才退出，在途请求能在优雅退出期内跑完")
    print()

# ---- 场景 3：预热与 liveness 的相互作用 ----
print("场景 3：慢启动实例没配 startupProbe 会怎样")
print("-" * 74)
slow_init_ms = 25000
liv_period, liv_fail = 1000, 3
kill_at = liv_period * liv_fail
print(f"  实例启动需要 {slow_init_ms} ms，liveness 周期 {liv_period}ms × 失败 {liv_fail} 次")
print(f"  → 第 {kill_at} ms 就被判定死亡并重启（此时它才初始化到 {kill_at/slow_init_ms*100:.0f}%）")
print(f"  → 永远启动不完：重启 → 再等 {slow_init_ms} ms → 再被杀，无限循环")
print(f"  ✅ 配了 startupProbe 后：liveness 在 startup 成功前不执行，"
      f"只要 startupProbe 的 failureThreshold×periodSeconds > {slow_init_ms} 就能起来")
print()

print("=" * 74)
print("判读")
print("=" * 74)
print("""  · readiness 的语义是"现在能不能接流量"，不是"进程还活着"。
    所以它必须包含预热判断——否则通过得太早，流量打在还没热的实例上
  · liveness 的语义是"这个进程还有救吗"。它绝不能包含下游依赖：
    依赖挂了不是我的错，重启我也修不好下游（M4 已量化：45 次重启 vs 0 次）
  · 摘流必须早于 SIGTERM：endpoint 更新是异步传播的，
    "先杀进程"会留下一个还在收流量的死实例窗口
  · 慢启动要有 startupProbe，否则 liveness 会把"正在启动"误判成"已经死了"
""")
