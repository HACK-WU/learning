# -*- coding: utf-8 -*-
"""
第 15 课 实验 A：触发器调用频次与资源占用模拟器
==========================================================================
目的：把「选哪种触发器」这个抽象决定，翻译成两个运维能感知的数字：
      ① 每天被调用多少次   ② 占掉多少 CPU 时间 / 会不会积压

纯标准库，不依赖 Docker，可直接接 CI。

--------------------------------------------------------------------------
⚠️ 假设值标注（诚实说明）
--------------------------------------------------------------------------
本脚本中**不依赖任何假设**的硬事实：
  · WAL flush 默认每 1 秒一次（官方 get-started/process 原文：
    "flushes data to the Write-Ahead Log (WAL) ... (by default, every second)"）
  · 1 天 = 86,400 秒（硬算术）
  · Core 的 query-file-limit 默认 432 个 Parquet 文件（官方 config-options 原文）
  · schedule 触发器每次运行只落进 1 个 gen1 桶 → 文件数 = 每天调度次数
    （L14 已核实，机制推理，非官方明文）

**属假设值**的部分：
  · 插件单次执行耗时 5 / 20 / 50 / 100 / 500 / 1000 ms 为**假设档位**，
    用于观察量级与临界点，不代表任何真实插件
  · 对照 4 的「初始 100 行/秒」为假设初值

要抓的是**量级关系与临界点**（单次耗时必须 < 触发周期、WAL 是 schedule 的
几万倍、写回同表 20 秒 exponential 爆炸），不是任何绝对数字。
"""

SEC_PER_DAY = 86_400
FILE_LIMIT = 432          # 官方默认 query-file-limit
WAL_FLUSH_SEC = 1         # 官方默认：WAL 每秒刷一次


def fmt_dur(sec):
    """把秒数格式化成人能读的时长。"""
    if sec < 1:
        return f"{sec:.2f} 秒"
    if sec < 60:
        return f"{sec:.0f} 秒"
    if sec < 3600:
        return f"{sec / 60:.1f} 分钟"
    if sec < 86_400:
        return f"{sec / 3600:.2f} 小时"
    return f"{sec / 86_400:.2f} 天"


def hr(title):
    print()
    print("=" * 80)
    print(title)
    print("=" * 80)


# ---------------------------------------------------------------- 对照 1
def c1():
    hr("对照 1：三种触发器，每天各被调用多少次（量级差多少倍）")

    print()
    print('官方原文（Core get-started/process）：')
    print('  WAL rows (table: or all_tables): ... when the database flushes')
    print('  data to the Write-Ahead Log (WAL) (by default, every second).')
    print()
    print("→ WAL 触发器的调用频率 = WAL 刷盘频率 = **每秒 1 次**，")
    print("  与你每秒写了 1 行还是 100 万行**无关**。")
    print()

    rows = [
        ("WAL（table:xxx / all_tables）", "每 1 秒", 86_400),
        ("schedule every:10m", "每 600 秒", 144),
        ("schedule every:1h", "每 3,600 秒", 24),
        ("schedule every:6h", "每 21,600 秒", 4),
        ("schedule every:1d", "每 86,400 秒", 1),
        ("request（HTTP 端点）", "由外部调用方决定", None),
    ]

    print(f"{'触发器规格':<32}{'周期':<18}{'每天调用次数':>14}{'相对 every:1d':>16}")
    print("-" * 80)
    for spec, period, n in rows:
        if n is None:
            print(f"{spec:<32}{period:<18}{'—（被动）':>14}{'—':>16}")
        else:
            print(f"{spec:<32}{period:<18}{n:>14,}{n:>16,}")

    print()
    print("💡 量级差：WAL 触发器是 every:1d 的 **86,400 倍**。")
    print("   → WAL 插件函数体里每多花 1 毫秒，一天就是 86.4 秒。")
    print("   → 绝大多数「定时任务」场景，schedule 才是正确的触发器类型。")


# ---------------------------------------------------------------- 对照 2
def c2():
    hr("对照 2：WAL 插件单次耗时 → 每天吃掉多少 CPU 时间（临界点在哪）")

    print()
    print("⚠️ 下面 5 / 20 / 50 / 100 / 500 / 1000 ms 是**假设档位**，")
    print("   用来观察量级与临界点；「每秒 1 次 × 86,400 秒」是官方默认值与硬算术。")
    print()

    print(f"{'单次耗时':<12}{'每天总耗时':<18}{'墙钟占比':<12}判读")
    print("-" * 80)

    verdicts = {
        5:    "几乎无感，健康区间",
        20:   "可接受；注意 Core 是单节点四功能竞争",
        50:   "开始挤压查询与写入",
        100:  "墙钟 10%，抖动时容易积压",
        500:  "危险：同步执行已占掉一半墙钟",
        1000: "❌ 临界：单次耗时 = 触发周期，永远追不上",
    }

    for ms in (5, 20, 50, 100, 500, 1000):
        total = ms / 1000.0 * SEC_PER_DAY
        pct = total / SEC_PER_DAY * 100
        print(f"{ms:>6} ms   {fmt_dur(total):<18}{pct:>7.1f}%    {verdicts[ms]}")

    print()
    print("🔴 硬边界（不依赖假设）：**单次耗时必须 < 触发周期**。")
    print("   对 WAL 触发器而言触发周期是 1 秒 —— 一旦插件单次跑满 1 秒，")
    print("   下一批已经在等你了，队列会单调增长直到 OOM。")
    print("   实用判据：WAL 插件单次 **P99 < 100 ms**，超了就该挪到 schedule 上去做。")


# ---------------------------------------------------------------- 对照 3
def c3():
    hr("对照 3：回扣 L14 —— schedule 触发器的周期同时决定了「能不能查」")

    print()
    print("L14 已核实：gen1-duration 按**时间**分桶（默认 10 分钟），")
    print("schedule 触发器每次运行只落进 1 个桶 → **文件数 = 每天调度次数**。")
    print()
    print("所以 schedule 的 every: 同时决定了两件事：")
    print("   ① 每天被调用几次（本实验对照 1）")
    print("   ② 该表 90 天后有多少个 Parquet 文件（能不能查）")
    print()

    print(f"{'调度周期':<14}{'每天文件数':>12}{'90 天文件数':>14}{'vs 432 上限':>14}{'Core 可查':>12}")
    print("-" * 80)

    plans = [
        ("every:10m", 144),
        ("every:1h", 24),
        ("every:6h", 4),
        ("every:1d", 1),
    ]

    for spec, per_day in plans:
        n90 = per_day * 90
        ok = "✅" if n90 <= FILE_LIMIT else "❌ 超限报错"
        ratio = f"{n90 / FILE_LIMIT:.1f}×"
        print(f"{spec:<14}{per_day:>12}{n90:>14,}{ratio:>14}{ok:>12}")

    print()
    print("→ 反推：90 × 每天文件数 ≤ 432 → 每天 ≤ 4.8 次 → **调度周期 ≥ 5 小时（取 6h）**。")
    print("→ 这条约束与降采样精度无关，只与**调度周期**有关（L14 结论）。")
    print()
    print("⚠️ 注意 WAL 触发器不受这条约束影响：")
    print("   WAL 触发器是**读**写入的数据，它自己不产生新的 gen1 桶；")
    print("   真正决定文件数的是「谁在往表里写」以及「多久写一次」。")


# ---------------------------------------------------------------- 对照 4
def c4():
    hr("对照 4：🔴 WAL 插件写回「被监听的表」= 指数爆炸（20 秒破 5,000 万行/秒）")

    print()
    print("官方示例插件里有一行看似多余的代码：")
    print()
    print("    # example to skip the table we're later writing data into")
    print('    if table_batch["table_name"] == "some_table":')
    print("        continue")
    print()
    print("它不是示例凑字数 —— 这是**防止写回递归**的唯一防线。")
    print("如果你用 all_tables 监听，并且把结果写回同一张表，数据流是这样的：")
    print()

    base = 100          # ⚠️ 假设初值：外部每秒写入 100 行
    rows = base

    print(f"{'第 n 秒':<10}{'本秒 flush 的行数':>20}{'插件写回行数':>16}{'累计写入行数':>18}")
    print("-" * 80)

    cum = 0
    milestones = (1, 2, 3, 5, 10, 15, 20)
    flushed_at_20 = 0
    for n in range(1, 21):
        flushed = rows
        written_back = rows        # 1 行进 → 1 行出
        cum += flushed + written_back
        if n in milestones:
            print(f"{n:>6} 秒{flushed:>20,}{written_back:>16,}{cum:>18,}")
        if n == 20:
            flushed_at_20 = flushed     # 记住第 20 秒的真实值
        rows = flushed + written_back   # 下一秒要处理的 = 本秒外部 + 本秒写回

    print()
    print(f"→ 第 20 秒：单秒要处理 **{flushed_at_20:,} 行** —— 约 5,000 万行/秒。")
    print(f"→ 第 21 秒：突破 **{rows:,} 行** —— 相当于每秒 1 亿行。")
    print("→ 任何规模的实例都会在几十秒内被自己写死，且**不会有任何报错**。")
    print()
    print("✅ 三种正解（任选其一，按推荐顺序）：")
    print("   ① 用 --trigger-spec \"table:源表\" 只监听源表，写回**另一张**表")
    print("      （最干净：从源头就不可能递归）")
    print("   ② 用 all_tables 时，在插件开头 continue 掉自己要写回的表")
    print("      （官方示例用的就是这招，必须自己记得写）")
    print("   ③ 写回另一个**数据库**（Core 共 5 个库额度，L6 硬限制）")
    print()
    print("📌 补充：InfluxDB 3.11 起 WAL 触发器会**跳过空 flush**")
    print("   （capped async trigger concurrency / bounded retries / WAL triggers")
    print("   that skip empty flushes）—— 能减少无效调用，但**不解决递归**：")
    print("   递归时每一批都有数据，不为空。")


# ---------------------------------------------------------------- 对照 5
def c5():
    hr("对照 5：插件的 CPU 开销在 Core 上为什么格外贵（回扣 L13）")

    print()
    print("L13 已核实：Core 是**单节点**，摄入 / 查询 / 压实 / 处理四类功能")
    print("竞争同一实例的资源（官方：Core does not include 升级版存储引擎）。")
    print()
    print("→ 处理引擎不是「旁边挂着的另一个进程」，它是**抢同一块 CPU 的第四个房客**。")
    print()

    budget = [
        ("WAL 插件 20 ms × 86,400 次/天", 20 / 1000 * 86_400, "≈ 一天 0.5 小时的 CPU，尚可"),
        ("WAL 插件 100 ms × 86,400 次/天", 100 / 1000 * 86_400, "≈ 一天 2.4 小时，等于少了 10% 的机器"),
        ("schedule every:6h × 50 ms", 4 * 0.05, "≈ 一天 0.2 秒，可以忽略"),
        ("schedule every:6h × 30 秒（拉外部 API）", 4 * 30, "≈ 一天 2 分钟，且尖峰时卡住别的活"),
    ]

    print(f"{'场景':<42}{'每天 CPU':>14}  判读")
    print("-" * 80)
    for name, sec, note in budget:
        print(f"{name:<42}{fmt_dur(sec):>14}  {note}")

    print()
    print("💡 结论：")
    print("   · WAL 插件要「短而快」—— 只做纯内存判断，不做网络 I/O，不做大查询")
    print("   · 需要查历史数据 / 调外部 API / 跑模型 → 一律放 schedule")
    print("   · 需要跑几十秒的重活 → schedule + --run-asynchronous")
    print("     （Enterprise 官方文档另有 --node-spec 可把触发器钉到指定节点）")


def main():
    print()
    print("*" * 80)
    print(" 第 15 课 实验 A：触发器调用频次与资源占用模拟器")
    print("*" * 80)
    print()
    print(" 📌 硬事实：WAL flush 每秒 1 次（官方默认值）｜ 432 文件上限（官方默认值）")
    print(" 📌 假设值：插件单次耗时档位、递归初值 100 行/秒")
    print(" 📌 要抓的是量级与临界点，不是绝对值")

    c1()
    c2()
    c3()
    c4()
    c5()

    print()
    print("=" * 80)
    print(" 对照总结（四条可落地判据）")
    print("=" * 80)
    for line in [
        "1. WAL 触发器每秒一次 = 86,400 次/天，是 every:1d 的 8.6 万倍 —— 默认别选它，",
        "   只有「必须在写入瞬间做判断」的场景（阈值告警、schema 校验）才值得。",
        "2. 单次耗时必须 < 触发周期；WAL 插件的实用红线是 P99 < 100 ms。",
        "3. schedule 的 every: 同时决定调用次数与文件数 → 长周期可查需 ≥ 6h（L14）。",
        "4. WAL 插件写回被监听的表 = 指数爆炸（15 秒破百万、20 秒破 5,000 万）；",
        "   用 table:源表 从源头杜绝。",
    ]:
        print("   " + line)
    print()


if __name__ == "__main__":
    main()
