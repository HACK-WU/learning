# -*- coding: utf-8 -*-
"""
L16 实验 B：自监控覆盖率与查询成本模拟器
=========================================
回答两个"上生产前必须算清"的问题：

  对照 1：三种自监控数据源，各自的覆盖面与盲区
  对照 2：Core 无 compactor，自监控数据自己撑多久会撞 432 文件上限
  对照 3：Grafana 面板刷新频率 → 一天的查询次数与成本量级
  对照 4：/metrics 抓一次有多少指标？抓取间隔对自监控数据量的影响

不依赖任何外部库，纯标准库，可直接在任意 Python 3.9+ 上跑。
"""
import math

# ========== 官方一手常量 ==========
FILE_LIMIT = 432          # Core query-file-limit 默认 432 个 Parquet 文件（回扣 L11）
GEN1_DURATION_MIN = 10    # gen1-duration 默认 10 分钟 → 每 10 分钟 1 个 Parquet 文件
SEC_PER_DAY = 86_400
FILES_PER_DAY = 144       # 144 = 86400 / 600（每 10 分钟一个文件）

# 自监控数据假设值（⚠️ 均为假设，脚本内会打印标记）
BYTES_PER_SAMPLE = 180        # ⚠️ 假设：一个 Prometheus 样本落库后约 180 字节
BYTES_PER_METRIC = 120        # ⚠️ 假设：一条时序行约 120 字节（沿用 L13/L14 口径）


def hr(title=""):
    if title:
        print("\n" + "=" * 76)
        print("  " + title)
        print("=" * 76)
    else:
        print("-" * 76)


def fmt_num(n):
    return f"{n:,.0f}"


def fmt_bytes(b):
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if abs(b) < 1024:
            return f"{b:,.1f} {unit}"
        b /= 1024
    return f"{b:,.1f} PB"


# ========== 对照 1：三种自监控数据源 ==========

def compare_sources():
    hr("对照 1：三条自监控数据源，各自的覆盖面与盲区")

    rows = [
        # 数据源, 拿得到, 拿不到, 落库?, 适合
        ("GET /health",
         "进程是否活着（200=OK, 500=不可用）",
         "一切内部状态：不返回版本、不看对象存储",
         "否", "K8s liveness 兜底 / 人工 curl"),
        ("GET /ready (3.10+)",
         "能否连通**底层对象存储**（200/503）",
         "业务指标（写入量、查询量、文件数）",
         "否", "✅ K8s readiness / LB 探针（L13 已讲）"),
        ("GET /metrics",
         "Prometheus 格式的内部运行时指标\n（内存池、查询耗时、WAL/文件计数等）",
         "长期趋势——它只是**当前值快照**，\n不抓取就等于没发生",
         "看你抓不抓", "✅ Prometheus/Grafana 面板与告警"),
        ("system.* 系统表",
         "结构化可 SQL 查询：\nsystem.queries / parquet_files /\nprocessing_engine_logs / last_caches …",
         "进程级指标（GC、内存池、线程）",
         "是（表）", "✅ SQL 派的排障入口（回扣 L15）"),
        ("system_metrics 插件",
         "主机级：CPU / 内存 / 磁盘 / 网络\n（内部依赖 psutil）",
         "InfluxDB 自身内部状态\n——它采的是**主机**，不是**数据库**",
         "是（表）", "✅ 主机健康；⚠️ 别当数据库监控用"),
    ]

    print(f"{'数据源':<22} {'落库':<6} {'盲区 / 注意'}")
    print("-" * 76)
    for src, has, lack, persist, use in rows:
        print(f"\n  ▸ {src}   [落库: {persist}]")
        print(f"      拿得到: {has}")
        print(f"      拿不到: {lack}")
        print(f"      适合  : {use}")

    print("\n" + "-" * 76)
    print("  ⭐ 最容易搞混的一条：")
    print("     system_metrics 这个**官方插件**采的是「跑 InfluxDB 的那台主机的 CPU/内存/磁盘」，")
    print("     它**不是** InfluxDB 的内部指标。名字里的 system 指的是 OS，不是 database。")
    print("     要监控 InfluxDB 自身，看 /metrics 与 system.* 系统表。")


# ========== 对照 2：自监控数据自己会不会撞 432 ==========

def compare_retention():
    hr("对照 2：自监控数据自己，多久会撞 432 文件上限？（Core 无 compactor）")

    print("  背景（回扣 L10/L11/L14）：")
    print(f"    · Core 无 compactor → 文件永不合并（回扣 L10）")
    print(f"    · gen1-duration 默认 {GEN1_DURATION_MIN} 分钟 → 每 {GEN1_DURATION_MIN} 分钟 1 个 Parquet 文件")
    print(f"    · query-file-limit 默认 {FILE_LIMIT} → 超限**直接报错**，不是变慢（回扣 L11）")
    print(f"    · 于是：{FILE_LIMIT} 文件 ÷ {FILES_PER_DAY} 文件/天 = "
          f"{FILE_LIMIT / FILES_PER_DAY:.2f} 天 ≈ {FILE_LIMIT * GEN1_DURATION_MIN / 60:.0f} 小时")

    print("\n  ⚠️ 关键认知：**文件数只跟墙钟有关，跟写了多少数据无关**（回扣 L15 的 WAL 触发器同理）。")
    print("     哪怕一天只写 1 条数据，只要服务开着，一天就是 144 个文件。")

    print("\n" + "-" * 76)
    print(f"  {'保留期':<12}{'文件数':>12}{'是否超限':>12}{'说明'}")
    print("-" * 76)

    for label, days in (("1 天", 1), ("2 天", 2), ("3 天", 3),
                        ("7 天", 7), ("30 天", 30), ("90 天", 90)):
        files = int(days * FILES_PER_DAY)
        over = files > FILE_LIMIT
        note = f"超 {files / FILE_LIMIT:.1f} 倍 → 查询报错" if over else "✅ 可查"
        print(f"  {label:<12}{files:>12,}{('❌ 是' if over else '✅ 否'):>12}   {note}")

    print("-" * 76)
    print(f"\n  → 结论：自监控数据跟业务数据完全一样，**最多只能查 {FILE_LIMIT / FILES_PER_DAY:.0f} 天**。")
    print("     想要更长的自监控历史，两条路（与 L14 的结论一致）：")
    print("       ① 降采样：用处理引擎定时把 /metrics 聚合到粗粒度层")
    print("       ② 上 Enterprise（有 compactor，文件会合并）")


# ========== 对照 3：Grafana 刷新频率 → 查询成本 ==========

def compare_dashboard_cost():
    hr("对照 3：Grafana 面板刷新频率 → 一天的查询次数")

    print("  场景：每个面板里有 N 个 query，面板每 T 秒自动刷新。")
    print("  公式：每天查询次数 = 面板数 × 每面板查询数 × (86,400 ÷ 刷新间隔秒)")
    print()
    print(f"  {'刷新间隔':<12}{'单面板(5 query)':>18}{'10 面板':>14}{'30 面板':>14}{'50 面板':>14}")
    print("-" * 76)

    for label, sec in (("5s", 5), ("10s", 10), ("30s", 30),
                       ("1m", 60), ("5m", 300)):
        per_day = SEC_PER_DAY // sec
        row = f"  {label:<12}"
        for panels in (1, 10, 30, 50):
            q = per_day * 5 * panels
            row += f"{q:>14,}"
        print(row)

    print("-" * 76)
    print("\n  ⚠️ 默认刷新间隔是很多人从未改过的一个数字。")
    print("     把 5s 改成 30s，同一批面板的查询量直接降到 1/6。")

    print("\n  💰 成本侧（回扣 L13 已核实）：")
    print("     官方博客算例：一个每 10 秒刷新的面板，一个月约 259,200 次查询 ≈ $31；")
    print("     20 个面板就是 $620/月。⚠️ 该算例是**每面板 1 个 query** 的口径")
    print(f"     （86,400÷10×30 = {86400 // 10 * 30:,}）；本表按每面板 5 个 query 计，")
    print("     同一档位要再 ×5 —— 引用官方数字时务必对齐口径。")
    print("     这是在 Cloud Serverless 上按查询计费的情形。")
    print("     → 自建 Core/Enterprise 不按次计费，但**查询抢的是同一块 CPU**（回扣 L13），")
    print("       代价从「账单」变成「写入与查询的延迟」。")


# ========== 对照 4：抓取间隔 → 自监控数据量 ==========

def compare_scrape_volume():
    hr("对照 4：/metrics 抓取间隔 → 自监控数据自己吃掉多少存储")

    print(f"  ⚠️ 假设值（脚本内显式标注）：每条时序行约 {BYTES_PER_METRIC} 字节，")
    print(f"     /metrics 一次暴露约 {METRIC_COUNT} 条时序。这些数量级用于看趋势，不是精确账单。")
    print()
    print("  场景：Prometheus 每 T 秒抓一次 /metrics，抓到的样本再写回 InfluxDB。")
    print()
    print(f"  {'抓取间隔':<12}{'每天样本数':>14}{'天增(MB)':>12}{'30 天(GB)':>12}{'90 天(GB)':>12}")
    print("-" * 76)

    for label, sec in (("5s", 5), ("10s", 10), ("15s", 15),
                       ("30s", 30), ("60s", 60)):
        samples_per_day = METRIC_COUNT * (SEC_PER_DAY / sec)
        bytes_per_day = samples_per_day * BYTES_PER_METRIC
        mb_day = bytes_per_day / 1024 / 1024
        gb_30 = bytes_per_day * 30 / 1024 ** 3
        gb_90 = bytes_per_day * 90 / 1024 ** 3
        print(f"  {label:<12}{samples_per_day:>14,.0f}{mb_day:>12,.1f}"
              f"{gb_30:>12,.2f}{gb_90:>12,.2f}")

    print("-" * 76)
    print("\n  → 抓取频率是**线性**的：15s → 30s，自监控存储直接减半。")
    print("  → 但这些样本即使只存 30 天，也已经**远超 Core 能查的 3 天窗口**（见对照 2）：")
    print("     存得下 ≠ 查得到。要能查长周期，必须先降采样。")


# ========== 总结 ==========

def summary():
    hr("五条落地结论")
    items = [
        ("① 自监控要分层，别指望一个端点",
         "/health 看进程活没活，/ready 看能否连对象存储，/metrics 看内部状态，\n"
         "        system.* 系统表看结构化元数据。四者覆盖面不同，缺一不可。"),
        ("② Core 的就绪探针用 GET /ready，不要只查 TCP",
         "无盘架构下进程活着 ≠ 能服务。这是 L13 已核实的一条，L16 把它接到 K8s 探针上。"),
        ("③ 自监控数据自己也在 432 文件限制内，最多查 3 天",
         "文件数 = 天数 × 144，跟数据量无关。想看更长历史必须降采样或上 Enterprise。"),
        ("④ Grafana 的刷新间隔是被忽略的查询放大器",
         "5s → 30s，查询量降到 1/6。自建环境代价是 CPU，云上代价是账单。"),
        ("⑤ system_metrics 插件采的是主机，不是数据库",
         "名字里的 system 指 OS。想监控 InfluxDB 自身，看 /metrics 和 system.queries。"),
    ]
    for t, d in items:
        print(f"\n  {t}")
        print(f"      {d}")

    hr("本实验的诚实说明")
    print("  ✅ 不依赖假设的部分：432 文件上限、144 文件/天、3 天可查窗口、")
    print("     /metrics 与 /health 的认证默认行为、Grafana 走 Flight SQL 需 HTTP/2。")
    print("  ⚠️ 假设值（仅用于看量级趋势，不要当精确账单引用）：")
    print(f"     每条时序行 {BYTES_PER_METRIC} 字节（沿用 L13/L14 口径的中位数）、")
    print(f"     /metrics 一次暴露 {METRIC_COUNT} 条时序（真实数量随版本与配置变化）。")
    print("  ⏳ 未实跑：真实 /metrics 抓取、Grafana 面板配置、system.* 表查询")
    print("     —— 编写环境无 Docker，需真实 InfluxDB 3 实例。")


METRIC_COUNT = 800   # ⚠️ 假设：/metrics 一次暴露的时序条数量级


def main():
    print("=" * 76)
    print("  L16 实验 B：自监控覆盖率与查询成本模拟器")
    print("=" * 76)
    print(f"  Core 硬约束：query-file-limit = {FILE_LIMIT} 文件 | "
          f"gen1-duration = {GEN1_DURATION_MIN} 分钟 | {FILES_PER_DAY} 文件/天")
    print(f"  ⚠️ 假设初值：{BYTES_PER_METRIC} 字节/行 | "
          f"{METRIC_COUNT} 条时序/次抓取（真实值随版本变化）")

    compare_sources()
    compare_retention()
    compare_dashboard_cost()
    compare_scrape_volume()
    summary()

    print("\n" + "=" * 76)
    print("  一句话总结：")
    print("  接生态不难，难的是**别让监控本身成为新的负担**——")
    print("  自监控数据一样受 432 文件限制，Grafana 一样抢写入的 CPU。")
    print("=" * 76)


if __name__ == "__main__":
    main()
