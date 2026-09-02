# -*- coding: utf-8 -*-
"""
L14 实验 A：分层保留与降采样成本模拟器

把「秒级 7 天 / 分钟级 90 天 / 小时级 1 年」这套经典策略的成本账算清楚，
并回答四个问题：
  1. 降采样到底省了多少？
  2. 降采样省的是「行数」还是「字节」？
  3. 在 Core 上，降采样层的文件数由什么决定？（这是本课最关键的一条）
  4. 降采样的隐藏成本是什么？

⚠️ 诚实说明（务必先读）：
  - 每点 120 字节、聚合行 128 字节、压缩比 25x：**假设值**
    （每点字节数取 L12 已核实典型区间 60-150 的中位；压缩比档位取自
      官方博客口径 "often 10-100x smaller" 区间内）
  - 文件数 144/天、432 文件上限、gen1-duration 10m、保留期单位换算：
    **官方默认值**，不依赖任何假设
  - 「文件数 ≈ 有数据写入的 gen1 时间桶数」：基于官方 internals 文档
    「每 10 分钟持久化一次」机制的**推理**，非官方明文结论
  - 结论要抓的是**数量级与结构关系**，不是绝对 GB 数
"""

# ---------- 假设参数（已标注） ----------
RAW_POINT_BYTES = 120      # 原始单点的压缩前字节数（含重复存储的 tag）
COMPRESS_RATIO = 0.04      # 典型 25x 压缩

# 聚合行的行宽拆解（压缩前）
AGG_TS = 8                 # 时间戳
AGG_VALUES = 8 * 4         # avg / min / max / count 四个聚合值
AGG_META = 8 * 3           # record_count / time_from / time_to 三个元数据列
AGG_TAGS = 60              # 保留的 tag（假设 2 个 tag，平均 30 字节）
AGG_OVERHEAD = 4           # 列/行元数据开销
AGG_ROW_BYTES = AGG_TS + AGG_VALUES + AGG_META + AGG_TAGS + AGG_OVERHEAD

# ---------- 官方默认值 ----------
GEN1_DURATION_MIN = 10              # gen1-duration 默认 10m
FILES_PER_DAY = 144                 # 86400 / (10*60)
QUERY_FILE_LIMIT = 432              # query-file-limit 默认


def raw_bytes(pps, days):
    """原始层存储字节数（压缩后）"""
    return pps * 86400 * days * RAW_POINT_BYTES * COMPRESS_RATIO


def agg_bytes(pps, days, src_interval_s, dst_interval_s):
    """降采样层存储字节数（压缩后）。返回 (字节数, 行数)"""
    row_ratio = src_interval_s / dst_interval_s
    rows = pps * 86400 * days * row_ratio
    return rows * AGG_ROW_BYTES * COMPRESS_RATIO, rows


def fmt(b):
    for unit in ("B", "KB", "MB", "GB", "TB", "PB"):
        if abs(b) < 1024.0:
            return "{:.1f} {}".format(b, unit)
        b /= 1024.0
    return "{:.1f} EB".format(b)


def line(ch="-", n=76):
    print(ch * n)


print("=" * 76)
print("L14 实验 A：分层保留与降采样成本模拟器")
print("=" * 76)
print()
print("【假设值】原始点 {} 字节 / 聚合行 {} 字节 / 压缩比 {:.0f}x".format(
    RAW_POINT_BYTES, AGG_ROW_BYTES, 1 / COMPRESS_RATIO))
print("【官方值】gen1-duration {}m → {} 文件/天 ／ 查询上限 {} 文件".format(
    GEN1_DURATION_MIN, FILES_PER_DAY, QUERY_FILE_LIMIT))
print()

PPS = 10000   # 1 万点/秒 —— 中等规模生产负载


# ---------------------------------------------------------------- 对照 1
line("=")
print("对照 1：全量保留 vs 三层降采样（1 万点/秒，覆盖 1 年）")
line("=")
print()

raw_1y = raw_bytes(PPS, 365)
print("【方案 X】不做任何降采样，原始精度存 1 年")
print("  存储量      : {}".format(fmt(raw_1y)))
print("  文件数      : {:,} 个".format(int(365 * FILES_PER_DAY)))
print("  Core 可查？ : ❌ 超限 {:.0f} 倍（上限 {}）".format(
    365 * FILES_PER_DAY / QUERY_FILE_LIMIT, QUERY_FILE_LIMIT))
print()

tiers = [
    ("第 1 层 · 原始秒级", 1, 1, 7),
    ("第 2 层 · 分钟级", 1, 60, 90),
    ("第 3 层 · 小时级", 60, 3600, 365),
]

total = 0.0
print("【方案 Y】三层分层保留（秒级 7 天 / 分钟级 90 天 / 小时级 1 年）")
print()
print("{:<20} {:>8} {:>10} {:>12} {:>12}".format(
    "层级", "保留期", "行数比", "存储量", "原始占比"))
line()
for name, src_i, dst_i, days in tiers:
    if src_i == dst_i:
        b = raw_bytes(PPS, days)
        ratio = 1
    else:
        b, _ = agg_bytes(PPS, days, src_i, dst_i)
        ratio = src_i / dst_i
    total += b
    print("{:<20} {:>8} {:>10} {:>12} {:>11.2%}".format(
        name, "{} 天".format(days),
        "1:{}".format(int(dst_i / src_i)) if src_i != dst_i else "—",
        fmt(b), b / raw_1y))
line()
print("{:<20} {:>8} {:>10} {:>12} {:>11.2%}".format(
    "合计", "1 年", "", fmt(total), total / raw_1y))
print()
print("💡 结论 1：三层方案的存储量是裸存 1 年的 {:.1f}%（省了 {:.1f}%）".format(
    total / raw_1y * 100, (1 - total / raw_1y) * 100))
print("   注意看第 1 层：7 天原始就占了 {:.0f}% 的量 —— ".format(
    raw_bytes(PPS, 7) / total * 100))
print("   **短保留期的原始层才是存储大头，降采样层的成本几乎可以忽略**。")
print()

# ---------------------------------------------------------------- 对照 2
line("=")
print("对照 2：降采样省的是「行数」还是「字节」？")
line("=")
print()
print("行宽拆解对比（压缩前）：")
print()
print("  原始点 : 时间戳 {}B + 1 个值 {}B + tag/开销 {}B = {} B".format(
    8, 8, RAW_POINT_BYTES - 16, RAW_POINT_BYTES))
print("  聚合行 : 时间戳 {}B + 4 个聚合值 {}B + 3 个元数据 {}B".format(
    AGG_TS, AGG_VALUES, AGG_META))
print("          + tag {}B + 开销 {}B = {} B".format(
    AGG_TAGS, AGG_OVERHEAD, AGG_ROW_BYTES))
print()
print("  → 聚合行比原始点**更宽**（{} B vs {} B），因为多了 7 个列。".format(
    AGG_ROW_BYTES, RAW_POINT_BYTES))
print()
print("{:<14} {:>12} {:>14} {:>12} {:>12}".format(
    "降采样目标", "行数比", "单行字节", "实际字节比", "净节省"))
line()
for label, dst in [("10 秒", 10), ("1 分钟", 60), ("5 分钟", 300), ("1 小时", 3600)]:
    row_ratio = 1.0 / dst
    byte_ratio = (AGG_ROW_BYTES * row_ratio) / RAW_POINT_BYTES
    print("{:<14} {:>12} {:>14} {:>11.3%} {:>11.2%}".format(
        label, "1:{}".format(dst), AGG_ROW_BYTES, byte_ratio, 1 - byte_ratio))
line()
print()
print("💡 结论 2：**降采样省的是行数，单行反而更宽**。")
print("   行数降到 1/60，字节只降到 {:.2%} —— 净节省 {:.1f}%，不是 98.3%。".format(
    (AGG_ROW_BYTES / 60) / RAW_POINT_BYTES,
    (1 - (AGG_ROW_BYTES / 60) / RAW_POINT_BYTES) * 100))
print("   那为什么总量上省了 96%？因为**保留期才是最大的乘数**：")
print("   第 1 层只留 7 天，第 3 层虽然宽，但只留 1/3600 的行数 × 1 年。")
print("   → 降采样 ≈ 用「更宽的行」换「极少的行 + 极长的保留期」。")
print()

# ---------------------------------------------------------------- 对照 3（核心）
line("=")
print("对照 3：⭐ Core 上降采样层的「文件数」由什么决定？")
line("=")
print()
print("这是本课最容易想错的一条。先看清机制：")
print()
print("  gen1-duration = 10m 是**按时间分桶**，不是按数据量分桶。")
print("  → 每个「有数据落入的 10 分钟桶」生成 1 个 parquet 文件。")
print("  → 文件数跟「写了多少行」**无关**，只跟「覆盖了多少个时间桶」有关。")
print()
print("  原始层：持续写入 → 每 10 分钟桶都有数据 → {} 文件/天".format(FILES_PER_DAY))
print("  降采样层：**按调度批量写入** → 每次调度只落进 1 个桶")
print("           → 文件数 = 每天调度次数（当调度周期 ≥ 10 分钟时）")
print()
print("⚠️ 这条推理基于官方 internals「每 {} 分钟持久化一次」的机制，".format(GEN1_DURATION_MIN))
print("   非官方明文结论，但可自行验证（看对象存储里 dbs/<db>/<table>/ 的文件数）。")
print()

schedules = [("every:1m", 1 / 60), ("every:10m", 1 / 6), ("every:1h", 1),
             ("every:6h", 6), ("every:1d", 24)]

print("{:<12} {:>10} {:>12} {:>14} {:>10}".format(
    "调度周期", "每天次数", "90 天文件数", "365 天文件数", "90 天可查?"))
line()
for label, hours in schedules:
    per_day = int(24 / hours)
    f90 = per_day * 90
    f365 = per_day * 365
    ok = "✅" if f90 <= QUERY_FILE_LIMIT else "❌ 超限"
    print("{:<12} {:>10} {:>12,} {:>14,} {:>10}".format(
        label, per_day, f90, f365, ok))
line()
print()
print("💡 结论 3（本课最关键的一条）：")
print("   **降采样层能不能查，取决于调度周期，不取决于降采样精度。**")
print()
print("   反推约束：要让 90 天可查，需 90 × 每天文件数 ≤ {}".format(QUERY_FILE_LIMIT))
print("   → 每天文件数 ≤ {:.1f} → **调度周期必须 ≥ 5 小时**（取 6h 留余量）".format(
    QUERY_FILE_LIMIT / 90))
print()
print("   所以「分钟级 90 天」这个经典配置，如果降采样任务跑 every:1h，")
print("   会生成 {:,} 个文件 —— 照样超限，**白降了**。".format(24 * 90))
print("   必须配 every:6h 或更低频率（或上 Enterprise 用 compactor 压实）。")
print()

# ---------------------------------------------------------------- 对照 4
line("=")
print("对照 4：降采样的隐藏成本 —— 双份存储期")
line("=")
print()
print("降采样不是「把原始数据变小」，是**额外写一份聚合数据**。")
print("在原始数据过期之前，你同时付两份存储的钱。")
print()
print("{:<12} {:>12} {:>12} {:>12} {:>14}".format(
    "时点", "原始层", "分钟级层", "合计", "vs 不降采样"))
line()
for label, d_raw, d_ds in [("第 1 天", 1, 0), ("第 7 天", 7, 0),
                           ("第 30 天", 7, 30), ("第 90 天", 7, 90)]:
    b_raw = raw_bytes(PPS, min(d_raw, 7))
    b_ds = agg_bytes(PPS, d_ds, 1, 60)[0] if d_ds else 0
    b_old = raw_bytes(PPS, d_raw)
    delta = (b_raw + b_ds) / b_old - 1 if b_old else 0
    print("{:<12} {:>12} {:>12} {:>12} {:>14}".format(
        label, fmt(b_raw), fmt(b_ds), fmt(b_raw + b_ds),
        "{:+.0%}".format(delta) if b_old else "—"))
line()
print()
print("💡 结论 4：**降采样的存储成本是前置的，且有一段「更贵」的窗口**。")
print("   第 90 天时合计 {}，比同期的裸存（{}）**多 {:.0f}%**。".format(
    fmt(raw_bytes(PPS, 7) + agg_bytes(PPS, 90, 1, 60)[0]),
    fmt(raw_bytes(PPS, 7)),
    ((raw_bytes(PPS, 7) + agg_bytes(PPS, 90, 1, 60)[0]) / raw_bytes(PPS, 7) - 1) * 100))
print("   真正的收益要等原始层开始过期（第 7 天之后）才逐步兑现。")
print("   → 容量规划必须按**峰值**算（原始层满 + 聚合层满），不是按稳态算。")
print()

# ---------------------------------------------------------------- 对照 5
line("=")
print("对照 5：保留期单位陷阱 —— 官方 mo/y 不是日历月/年")
line("=")
print()
print("官方 data-retention 页明文：")
print("  mo = month (30 days)   ← 不是日历月")
print("  y  = year (365 days)   ← 不是日历年（闰年 366 天）")
print("  ⚠️ 不支持 m（分）和 s（秒）单位")
print()
print("{:<10} {:>12} {:>28}".format("写法", "实际天数", "日历对照"))
line()
pairs = [("1mo", 30, "1 个日历月 ≈ 30.4 天（少 0.4 天）"),
         ("3mo", 90, "3 个日历月 ≈ 91.3 天（少 1.3 天）"),
         ("1y", 365, "日历年 = 365 或 366 天（闰年少 1 天）"),
         ("90d", 90, "= 3mo（等价）"),
         ("1y6mo", 545, "365 + 6×30 = 545 天")]
for label, days, cal in pairs:
    print("{:<10} {:>12} {:>28}".format(label, days, cal))
line()
print()
print("💡 结论 5：写 3mo 得到 90 天，而 3 个自然月实际是 91.3 天")
print("   → **少留了 1.3 天**。合规场景（必须留满 N 个自然月）要按天数换算。")
print("   ⚠️ 另一个坑：Core 的 retention 设为 0（0d/0h）表示**全部立即删除**，")
print("      这与 1.x/2.x「0d = 永久保留」**完全相反** —— 升级迁移时是高危操作。")
print()

# ---------------------------------------------------------------- 对照 6
line("=")
print("对照 6：删了 ≠ 腾出空间（软删除宽限期）")
line("=")
print()
print("官方 config-options（Core）默认值：")
print("  --delete-grace-period           24h    ← 硬删除前的宽限期")
print("  --retention-check-interval      30m    ← 保留期检查间隔")
print("  --gen1-lookback-duration        24h    ← 启动时回填 gen1 索引的回溯窗口")
print()
print("⚠️ 冲突提示：官方 3.2 发布博客写「default 72-hour grace period」，")
print("   但 config-options 页的默认值是 **24h** —— 以 config-options 为准。")
print()
print("时间线（delete-grace-period = 24h）：")
print()
print("  T+0      执行 delete table --hard-delete now")
print("           └ 表立刻不可查询，内部重命名为 <table>-<timestamp>")
print("  T+0~+24h 宽限期内：数据**仍在磁盘上**，重命名后的表**仍可查询**")
print("  T+24h    宽限期结束：parquet 文件从对象存储删除，catalog 条目移除")
print("  T+24h+   磁盘空间才真正回收")
print()
print("💡 结论 6：**--hard-delete now 的 now 是「现在开始宽限期」，")
print("   不是「现在立刻抹掉」**。腾空间要等 24 小时。")
print()
print("   ⚠️ 已知 issue #27200（2026-02）：若节点删除后不再接收写入")
print("      （不触发 snapshot），文件清理可能**迟迟不发生**。")
print("      → 边缘 / 低写入部署做删除后，务必观察 catalog 是否真的清理。")
print()

line("=")
print("实验 A 结束")
line("=")
