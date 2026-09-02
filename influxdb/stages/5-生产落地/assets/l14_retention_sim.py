# -*- coding: utf-8 -*-
"""
L14 实验 B：Core 保留期硬边界检查器

Core 的 retention 有四条**不会报错、但会咬人**的硬边界：
  1. 保留期只能在建库时设定，之后不可改（immutable）
  2. 单位是「固定换算」而非日历：mo = 30 天，y = 365 天
  3. retention = 0 表示「立刻全删」（与 1.x/2.x 的 0d = 永久 完全相反）
  4. 单位不支持 m / s；最短实际保留期是 1h

这个脚本把四条边界做成可自检的规则，输入你的需求，输出能不能配、
该怎么配，以及踩了哪条边界。纯标准库实现，可直接挂 CI 做建库前校验。

所有数值均来自官方文档明文，**不含假设值**。
"""

# ---------- 官方明文（docs.influxdata.com/influxdb3/core/reference/internals/data-retention）----------
UNIT_DAYS = {
    "h": 1 / 24,
    "d": 1,
    "w": 7,
    "mo": 30,        # 官方：month (30 days)
    "y": 365,        # 官方：year (365 days)
}
UNSUPPORTED_UNITS = ("m", "s")       # 官方：Minute (m) and second (s) units are not supported
MIN_PRACTICAL = "1h"                 # 官方：The practical minimum retention period is 1 hour
INFINITE = "none"                    # 官方：Use none to set an infinite retention period

CALENDAR_MONTH = 30.44               # 365.25 / 12，用于对比「自然月」
CALENDAR_YEAR = 365.25               # 含闰年


def parse_duration(s):
    """解析官方 duration 写法，返回 (天数, 错误信息)。支持组合写法如 30d12h。"""
    s = s.strip()
    if s == "none":
        return None, None
    if not s:
        return None, "空值：请写具体时长或 none"
    if " " in s:
        return None, "包含空格（官方禁止）"
    if s.startswith("-"):
        return None, "负数（官方禁止）"

    import re
    tokens = re.findall(r"(\d+(?:\.\d+)?)(mo|[a-zA-Z]+)", s)
    if not tokens or "".join(num + unit for num, unit in tokens) != s:
        return None, "无法解析（格式应为 数字+单位，如 30d / 1y6mo / 30d12h）"

    total_days = 0.0
    for num, unit in tokens:
        unit = unit.lower()
        if unit in UNSUPPORTED_UNITS:
            return None, "单位 '{}' 不支持（官方：不支持分和秒）".format(unit)
        if unit not in UNIT_DAYS:
            return None, "未知单位 '{}'（合法：h / d / w / mo / y）".format(unit)
        total_days += float(num) * UNIT_DAYS[unit]
    return total_days, None


def calendar_days(s):
    """按自然月/年换算的天数，用于与官方固定换算对比。无 mo/y 则返回 None。"""
    import re
    tokens = re.findall(r"(\d+(?:\.\d+)?)(mo|[a-zA-Z]+)", s)
    if not tokens:
        return None
    total = 0.0
    has_cal_unit = False
    for num, unit in tokens:
        unit = unit.lower()
        if unit == "mo":
            total += float(num) * CALENDAR_MONTH
            has_cal_unit = True
        elif unit == "y":
            total += float(num) * CALENDAR_YEAR
            has_cal_unit = True
        elif unit in UNIT_DAYS:
            total += float(num) * UNIT_DAYS[unit]
    return total if has_cal_unit else None


def line(ch="-", n=76):
    print(ch * n)


print("=" * 76)
print("L14 实验 B：Core 保留期硬边界检查器")
print("=" * 76)
print()
print("规则来源：官方文档 data-retention 页（Core）")
print("  ① 保留期**只能在建库时设定**，之后不可改（immutable）")
print("  ② 单位固定换算：mo = 30 天，y = 365 天（**不是日历**）")
print("  ③ retention = 0（0d/0h）→ **立刻全删**（与 1.x/2.x 相反）")
print("  ④ 不支持 m / s 单位；最短实际保留期 1h")
print()

# ---------------------------------------------------------------- 场景 1
line("=")
print("场景 1：解析合法写法 —— 看清 mo/y 的真实天数")
line("=")
print()
print("{:<12} {:>12} {:>14} {:>16}".format(
    "写法", "解析天数", "自然月/年对照", "偏差"))
line()
samples = ["1h", "24h", "7d", "4w", "1mo", "3mo", "90d", "1y", "1y6mo", "30d12h", "2w3d"]
for s in samples:
    days, err = parse_duration(s)
    if err:
        print("{:<12} {:>12} {:>14} {:>16}".format(s, "—", err, "—"))
        continue
    cal = calendar_days(s)
    if cal is None:
        cal_show, dev = "—", "—"
    else:
        cal_show = "{:.1f} 天".format(cal)
        dev = "{:+.1f} 天".format(days - cal)
    print("{:<12} {:>12.2f} {:>14} {:>16}".format(s, days, cal_show, dev))
line()
print()
print("💡 关键：3mo = 90 天，而 3 个自然月 ≈ 91.3 天 → **少留 1.3 天**")
print("   1y = 365 天，而平均日历年 ≈ 365.25 天（闰年 366 天）→ **少留 0.25~1 天**")
print("   1y6mo = 545 天，而 1 年 + 6 个自然月 ≈ 547.9 天 → **少留 2.9 天**")
print("   → 合规场景（必须留满 N 个自然月/年）请用天数写，别用 mo/y")
print()

# ---------------------------------------------------------------- 场景 2
line("=")
print("场景 2：非法写法 —— 这些会在建库时直接失败")
line("=")
print()
print("{:<16} {:>10} {:>44}".format("输入", "结果", "原因"))
line()
bad_samples = ["30m", "45s", "-7d", "7 d", "7x", "abc", "0d", "0h", ""]
for s in bad_samples:
    if s in ("0d", "0h"):
        print("{:<16} {:>10} {:>44}".format(
            repr(s), "⚠️ 可建", "但表示「立刻全删」——与 1.x/2.x 的 0d=永久相反"))
        continue
    days, err = parse_duration(s)
    status = "❌ 拒绝" if err else "✅ 通过"
    print("{:<16} {:>10} {:>44}".format(repr(s), status, err or ""))
line()
print()
print("💡 高危迁移陷阱：**1.x / 2.x 里 0d 表示永久保留，Core 里 0d 表示立刻全删**。")
print("   从旧版本迁移脚本时，看到 retention=0 务必逐一核对。")
print()

# ---------------------------------------------------------------- 场景 3
line("=")
print("场景 3：保留期 → 文件数 → Core 能不能查（建库前必查）")
line("=")
print()
print("约束：Core 的 query-file-limit 默认 432 文件，gen1-duration 默认 10m")
print("      → 原始层持续写入时 = 144 文件/天 = 432 文件 / 3 天")
print()
print("{:<12} {:>12} {:>14} {:>16}".format(
    "保留期写法", "解析天数", "原始层文件数", "Core 可查?"))
line()
for s in ["1h", "12h", "1d", "2d", "3d", "7d", "30d", "90d", "1y"]:
    days, err = parse_duration(s)
    if err:
        continue
    files = int(days * 144)
    ok = "✅ 可查" if files <= 432 else "❌ 超限（报错，不是变慢）"
    print("{:<12} {:>12.2f} {:>14,} {:>16}".format(s, days, files, ok))
line()
print()
print("💡 **这正是 L13 那条结论的另一面**：")
print("   保留期设得越长，数据越老，但**只要超 3 天就查不了**。")
print("   → 在 Core 上，长保留期 = 能存不能查 = 事实上的冷备份")
print("   → 要「能存又能查」，必须靠降采样层（文件数由调度频率决定，见实验 A 对照 3）")
print()

# ---------------------------------------------------------------- 场景 4
line("=")
print("场景 4：改保留期 —— Core 的唯一路径")
line("=")
print()
print("官方原文（Core data-retention 页）：")
print("  \"Retention periods are immutable in Core. In InfluxDB 3 Core, retention")
print("   periods can only be set when creating a database and cannot be changed")
print("   afterward. If you need to change a retention period, you must create a")
print("   new database with the desired retention period and migrate your data.\"")
print()
print("→ 所以改保留期的**唯一官方路径**是：")
print()
print("   1. 新建目标库（带想要的保留期）")
print("      influxdb3 create database --retention-period 30d metrics_new")
print()
print("   2. 迁移数据（SQL 侧写入，注意保留期窗口内的数据才有效）")
print("      influxdb3 query --database metrics_old \\")
print("        \"SELECT * INTO metrics_new.<table> FROM <table>\"")
print()
print("   3. 校验后再切应用写入、删旧库")
print("      influxdb3 delete database metrics_old --hard-delete now")
print()
print("⚠️ 但这里有个**死结**（Core 专属）：")
print("   步骤 2 的 SELECT 本身就受 432 文件限制！")
print("   → 原库保留期若 > 3 天，你**查不出全量数据**去迁移")
print("   → 只能迁最近 3 天，或者用第三方工具直读对象存储里的 parquet")
print()
print("✅ 这也是 Enterprise 的核心卖点之一：保留期**可改**，且有 compactor 解除文件数限制")
print()

# ---------------------------------------------------------------- 场景 5
line("=")
print("场景 5：决策清单 —— 建库前逐条打勾")
line("=")
print()
checklist = [
    ("保留期确认", "业务真正需要查多久？不是「想存多久」"),
    ("单位换算", "用了 mo/y 吗？按 30/365 天换算是否够（自然月会少留）"),
    ("零值陷阱", "脚本里有没有从 1.x/2.x 带过来的 0d？Core 里那是「立刻全删」"),
    ("单位合法性", "有没有用 m / s？Core 不支持，建库会失败"),
    ("最短期下限", "是否 ≥ 1h？更短没有实际意义"),
    ("文件数预演", "保留期天数 × 144 是否 ≤ 432？（否则查不了）"),
    ("降采样配套", "若要长保留，降采样任务的调度周期是否 ≥ 6h？"),
    ("改期预案", "接受「改保留期 = 重建库 + 迁移」吗？不接受就上 Enterprise"),
    ("双份成本", "容量是否按「原始层满 + 聚合层满」的峰值算？"),
    ("删除时滞", "接受硬删除后 24h 才真正腾出空间吗？"),
]
line()
print("{:<4} {:<14} {}".format("#", "检查项", "要问自己的问题"))
line()
for i, (item, q) in enumerate(checklist, 1):
    print("{:<4} {:<14} {}".format(i, item, q))
line()
print()
print("💡 口诀：**先问查多久，再定保留期；单位别用 mo，零值会全删；")
print("   超三天查不了，改期等于重建**。")
print()

line("=")
print("实验 B 结束")
line("=")
