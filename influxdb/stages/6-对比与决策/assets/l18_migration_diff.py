#!/usr/bin/env python3.11
# -*- coding: utf-8 -*-
"""
L18 实验 A：三代差异清单检查器（1.x / 2.x -> 3.x）

做什么：
    把一份「从 1.x 或 2.x 迁到 3.x」的迁移清单逐条体检，判定每一条在 3.x 的真实行为，
    分为三档：

        [直连]  原样可用，或只需换端点 / 换参数名（改了立刻能验证）
        [改写]  语义还在，但写法必须改（术语 / 查询语言 / 保留期单位 / 调度机制）
        [危险]  照抄会报错，或更糟 —— 不报错，但行为与你期望相反（静默语义反转）

    本课最关心的就是第三档里的「静默」那一类：它不会让你的迁移失败，
    它会让你的迁移「成功」，然后在你没注意的时候把数据删光。

不做什么：
    不连接任何数据库，不发送任何 HTTP 请求，不读任何配置文件。
    全部结论来自官方一手文档 + 本课程前序课已核实的条目，每条判定都带 evidence（出处）。

运行：
    C:\\Users\\v_wypgwu\\.local\\bin\\python3.11.exe l18_migration_diff.py

出处图例：
    官方   官方文档原文（docs.influxdata.com、官方博客、官方 release notes）
    已核实 本课程前序课已核实并写入 00-学习档案.md 的条目（本脚本不重复查证）
"""

from dataclasses import dataclass, field
from typing import Dict, List, Optional, Tuple

# ---------------------------------------------------------------------------
# 一、官方一手常量（每条都标出处，改动前请先回原文核对）
# ---------------------------------------------------------------------------

# 官方：InfluxDB 数据模型术语映射
# 出处 docs.influxdata.com/influxdb3/enterprise/write-data/best-practices/schema-design
#   "Bucket in InfluxDB v2 ... is synonymous with database in InfluxDB 3 Enterprise.
#    Measurement in InfluxDB v1, v2 ... is synonymous with table in InfluxDB 3 Enterprise."
TERM_MAP: List[Tuple[str, str, str]] = [
    ("v1 db / retention_policy", "database", "库与保留策略已合并为一个概念"),
    ("v2 bucket", "database", "官方原话 is synonymous with"),
    ("v1/v2 measurement", "table", "官方原话 is synonymous with"),
    ("v1/v2 tag key", "tag column", "列，类型为 string dictionary"),
    ("v1/v2 field key", "field column", "列，类型可为 int64/float64/uint64/bool/string"),
    ("v1/v2 point timestamp", "time column", "纳秒精度，永不为 null"),
]

# 官方：三代写入端点的时间戳精度支持矩阵
# 出处 docs.influxdata.com/influxdb3/core/write-data （"Timestamp precision across write APIs"）
# 行 = 精度语义；列 = (v1 /write, v2 /api/v2/write, v3 /api/v3/write_lp)
# 值为 None 表示该端点不支持该精度
PRECISION_MATRIX: List[Tuple[str, Optional[str], Optional[str], Optional[str]]] = [
    ("自动检测", None, None, "auto"),
    ("秒", "s", "s", "second"),
    ("毫秒", "ms", "ms", "millisecond"),
    ("微秒", "u 或 µ", "us", "microsecond"),
    ("纳秒", "ns", "ns", "nanosecond"),
    ("分钟", "m", None, None),
    ("小时", "h", None, None),
]
PRECISION_DEFAULT = ("纳秒", "纳秒", "auto（按量级猜测）")

# 官方：v3 自动精度检测的阈值（量级分档）
# 出处 官方 write-data 页 "Auto precision detection"（L4 已核实，本脚本不重复查证）
AUTO_THRESHOLDS: List[Tuple[str, str, int]] = [
    ("< 5e9", "秒", 1_000_000_000),
    ("< 5e12", "毫秒", 1_000_000),
    ("< 5e15", "微秒", 1_000),
    (">= 5e15", "纳秒", 1),
]

# InfluxDB 3 Core 硬限制（官方 Core 页，L6 已核实）
CORE_MAX_DATABASES = 5
CORE_MAX_TABLES = 2000
CORE_MAX_COLUMNS = 500

# 保留期语义（三段式，本课的「高危项」核心）
# 1.x：DURATION INF 表示永久（官方 v1 manage-database 页）
# 2.x：bucket retention = 0 表示永久
# 3.x：0（0d/0h）= 立刻全删（官方 config-options，L14 已核实）
V1_INFINITE = "INF"
V2_INFINITE_SECONDS = 0
V3_ZERO_RETENTION = "0d"


# ---------------------------------------------------------------------------
# 二、数据结构
# ---------------------------------------------------------------------------

LEVEL_OK = "OK"        # 直连
LEVEL_REWRITE = "RW"   # 改写
LEVEL_DANGER = "DG"    # 危险

LEVEL_LABEL = {
    LEVEL_OK: "直连",
    LEVEL_REWRITE: "改写",
    LEVEL_DANGER: "危险",
}


@dataclass
class CheckItem:
    """迁移清单里的一条。"""
    iid: str
    src: str                 # 来源版本：1.x / 2.x / 通用
    what: str                # 迁移项
    action: str              # 到 3.x 该怎么做
    level: str               # 档位
    silent: bool = False     # 是否「静默」——不报错但行为相反
    evidence: str = ""       # 出处
    note: str = ""           # 补充


@dataclass
class RetentionCase:
    """保留期翻译的一个案例。"""
    src_ver: str
    src_expr: str
    src_meaning: str
    naive: str               # 照抄/直觉翻译的结果
    naive_result: str        # 照抄会发生什么
    correct: str             # 正确写法
    silent: bool = False
    # 静默还分两种，性质完全不同，必须分开标：
    #   reverse = 方向反了（想永久，结果全删）—— 灾难级
    #   drift   = 方向没错，幅度偏了（想留 91.3 天，只留 90 天）—— 合规级
    kind: str = ""


KIND_LABEL = {
    "reverse": "静默·语义反转",
    "drift": "静默·幅度偏差",
}


# ---------------------------------------------------------------------------
# 三、迁移清单（17 条，全部带出处）
# ---------------------------------------------------------------------------

def build_checklist() -> List[CheckItem]:
    return [
        CheckItem(
            "M01", "2.x", "术语 bucket",
            "bucket 与 database 同义，走 /api/v2/write?bucket= 时参数名都不用改",
            LEVEL_OK,
            evidence="官方 schema-design 页 is synonymous with",
        ),
        CheckItem(
            "M02", "通用", "术语 measurement",
            "measurement 与 table 同义，行协议第一个字段照写，SQL 里称为表",
            LEVEL_OK,
            evidence="官方 schema-design 页 is synonymous with",
        ),
        CheckItem(
            "M03", "1.x", "db + retention_policy 两级命名",
            "合并为单个 database；若要用 InfluxQL 查询，库名必须写成 db/rp 形式",
            LEVEL_REWRITE,
            evidence="官方 Core create database 页 InfluxQL DBRP 命名约定",
            note="否则 InfluxQL 找不到库。注意库名带斜杠后路径要转义",
        ),
        CheckItem(
            "M04", "1.x", "写入端点 /write",
            "原样保留，v1 客户端库与 Telegraf outputs.influxdb 可直接指向 3.x",
            LEVEL_OK,
            evidence="官方 Core get-started：三个写入端点",
        ),
        CheckItem(
            "M05", "2.x", "写入端点 /api/v2/write",
            "原样保留，v2 客户端库可用；但 organization 须留空串",
            LEVEL_OK,
            evidence="官方 Core get-started；organization 空串为 L16 已核实",
        ),
        CheckItem(
            "M06", "1.x", "precision=m 或 precision=h",
            "先换算成秒或毫秒再写；分钟/小时精度只有 v1 端点支持",
            LEVEL_DANGER,
            evidence="官方 write-data 页精度矩阵：minute/hour 两行 v2/v3 均为不支持",
            note="迁到 v2/v3 端点时会直接失败，属「响亮的」失败，反而不是最危险的",
        ),
        CheckItem(
            "M07", "1.x", "precision=s（单个字母缩写）",
            "v3 端点显式写全拼 second；缩写形式在部分集成文档里出现，但官方 Core 页给的是全拼",
            LEVEL_REWRITE,
            evidence="官方 v3-write-lp 页列举 auto/nanosecond/microsecond/millisecond/second",
            note="官方文档冲突：AWS 集成页写 (ns, us, ms, s)，官方 Core 页写全拼。取全拼为保守口径",
        ),
        CheckItem(
            "M08", "1.x", "CREATE RETENTION POLICY ... DURATION INF（永久保留）",
            "建库时干脆不传 --retention-period；绝不能写成 0d",
            LEVEL_DANGER,
            silent=True,
            evidence="1.x INF 官方 v1 manage-database 页；3.x 0d 语义为 L14 已核实",
            note="见本报告对照 4 专项",
        ),
        CheckItem(
            "M09", "2.x", "bucket retention = 0（永久保留）",
            "同上：不传 --retention-period；绝不能写成 0d",
            LEVEL_DANGER,
            silent=True,
            evidence="2.x retention=0 即无限；3.x 0d 语义为 L14 已核实",
            note="这是全课最贵的一个字符：0 在 2.x 是「永远」，在 3.x 是「立刻」",
        ),
        CheckItem(
            "M10", "通用", "同一个表里 tag 与 field 同名",
            "改掉其中一个名字，导出前就要改（导出后再改要重写整个文件）",
            LEVEL_DANGER,
            evidence="官方 schema-design 页 Do not use duplicate names for tags and fields",
            note="1.x 会静默改名，3.x 是写入失败 —— 迁移前必须自查",
        ),
        CheckItem(
            "M11", "通用", "单表列数接近或超过 500",
            "拆表或合并稀疏字段；超过 Core 列上限写入直接失败",
            LEVEL_DANGER,
            evidence=f"官方 Core 限制：列 {CORE_MAX_COLUMNS}（L6 已核实）",
        ),
        CheckItem(
            "M12", "1.x", "Continuous Query（CQ）降采样",
            "改写为处理引擎的 scheduled 触发器 + Python 插件，或外部调度跑 SQL",
            LEVEL_REWRITE,
            evidence="官方 GA 博客：插件系统是 CQ / Tasks / Kapacitor 的自然继承者",
            note="L14 已核实：降采样层能否查取决于调度周期，不是精度",
        ),
        CheckItem(
            "M13", "2.x", "Flux Task 与 Flux 查询",
            "用 Explorer 1.9 的 Flux to SQL converter（beta）转，再人工逐行复核",
            LEVEL_REWRITE,
            evidence="官方 GA 博客：Flux 无直接兼容层；官方 Explorer 1.9 发布说明",
            note="官方自己提醒 converter 是 AI 生成、输出会变，必须复核后再跑",
        ),
        CheckItem(
            "M14", "1.x", "Kapacitor 告警",
            "官方称仍兼容，但推荐的落点是处理引擎的 HTTP/定时触发器 + Notifier 插件",
            LEVEL_REWRITE,
            evidence="官方 GA 博客：Kapacitor 和 Telegraf 仍然与 InfluxDB 3 兼容",
            note="L15 已核实：装告警必须「检测器 + Notifier」两件套",
        ),
        CheckItem(
            "M15", "通用", "库数量超过 5 个",
            "合并业务线或改用 Enterprise（Core 库上限 5）",
            LEVEL_DANGER,
            evidence=f"官方 Core 限制：库 {CORE_MAX_DATABASES}（L6 已核实）",
            note="1.x 里一个 db 拆多个 rp 的写法，在 Core 上会被迫摊平成多个库，很容易撞这条",
        ),
        CheckItem(
            "M16", "通用", "表的 tag 集合",
            "首次写入决定 tag 列集合与顺序，之后不可改；新 tag 可以加，已有 tag 的定义不能动",
            LEVEL_REWRITE,
            evidence="官方 schema-design 页 the tag column definitions for a table are immutable",
            note="导出导入时，第一条数据的 tag 顺序就是永久顺序，要先想清楚",
        ),
        CheckItem(
            "M17", "1.x", "保留期单位 3mo / 1y",
            "mo = 30 天、y = 365 天固定换算，不是日历月/年；不支持 m 和 s 单位",
            LEVEL_REWRITE,
            evidence="L14 已核实：3mo = 90 天 vs 三个自然月 91.3 天",
            note="对合规留存场景，这 1.3 天的差可能是要解释的",
        ),
    ]


# ---------------------------------------------------------------------------
# 四、保留期语义反转专项
# ---------------------------------------------------------------------------

def build_retention_cases() -> List[RetentionCase]:
    return [
        RetentionCase(
            "1.x", "DURATION INF", "永久保留",
            "0d", f"库建成后立刻全删（{V3_ZERO_RETENTION} = 立刻全删）",
            "建库时不传 --retention-period",
            silent=True, kind="reverse",
        ),
        RetentionCase(
            "2.x", "retention = 0", "永久保留",
            "0d", f"库建成后立刻全删（{V3_ZERO_RETENTION} = 立刻全删）",
            "建库时不传 --retention-period",
            silent=True, kind="reverse",
        ),
        RetentionCase(
            "1.x", "DURATION 7d", "保留 7 天",
            "7d", "正确", "7d（这个不用改）",
        ),
        RetentionCase(
            "2.x", "retention = 604800（秒）", "保留 7 天",
            "604800", "单位错了 —— 3.x 收的是时间段字符串，不是秒数",
            "7d",
        ),
        RetentionCase(
            "1.x", "DURATION 3mo", "保留三个自然月（约 91.3 天）",
            "3mo", "实际只留 90 天，比预期少 1.3 天",
            "3mo 并接受 90 天口径，或改 92d",
            silent=True, kind="drift",
        ),
        # 下面两条是「已知的雷同场景」：不是新坑，是同一个坑长在不同的地方。
        # 列出来是为了让迁移清单能照抄排查顺序，而不是每次都重新推理一遍。
        RetentionCase(
            "通用", "降采样库想留 90 天", "保留 90 天",
            "90d + 处理引擎 every:1h",
            "文件数 = 每天 24 个 x 90 天 = 2,160，超过 432 上限 —— 存得下但查不到",
            "每分辨率独立建库，且调度周期取 every:6h（L14 已核实）",
            silent=True, kind="reverse",
        ),
        RetentionCase(
            "通用", "合规库要求留满 3 个日历年", "保留 3 年",
            "3y", "y = 365 天固定换算，3y = 1,095 天；三个日历年含闰年为 1,096 天",
            "改 1096d 显式指定，并把口径写进说明材料",
            silent=True, kind="drift",
        ),
    ]


def translate_retention(src_ver: str, raw: str) -> Tuple[str, str]:
    """
    把 1.x / 2.x 的保留期写法翻译成 3.x 的 --retention-period 参数值。
    返回 (翻译结果, 说明)。
    """
    text = str(raw).strip()

    if src_ver == "1.x":
        if text.upper() == V1_INFINITE:
            return ("<不传参数>", "永久保留在 3.x 里是「不设保留期」，不是 0d")
        if text.lower().endswith(("d", "h", "w", "mo", "y")):
            return (text, "时间段写法可直接沿用，注意 mo=30 天 / y=365 天是固定换算")
        return (text + "  <需人工确认单位>", "只接受时间段字面量，不接受秒数")

    if src_ver == "2.x":
        try:
            seconds = int(text)
        except ValueError:
            return (text + "  <需人工确认单位>", "只接受时间段字面量，不接受秒数")
        if seconds == V2_INFINITE_SECONDS:
            return ("<不传参数>", "0 秒在 2.x 是永久；在 3.x 里 0d 是立刻全删 —— 千万别直译")
        days = seconds // 86400
        rem = seconds % 86400
        if rem == 0:
            return (f"{days}d", "秒数换算为天；2.x 的 0 不等于 3.x 的 0")
        hours = rem // 3600
        return (f"{days}d{hours}h", "秒数换算为天+小时；注意保留期最短实际为 1h")

    return (text + "  <未知来源版本>", "只处理 1.x / 2.x")


# ---------------------------------------------------------------------------
# 五、打印
# ---------------------------------------------------------------------------

WIDTH = 78


def hr(ch: str = "=") -> None:
    print(ch * WIDTH)


def title(text: str) -> None:
    print()
    hr("=")
    print(text)
    hr("=")


def main() -> None:
    title("L18 实验 A：三代差异清单检查器（1.x / 2.x -> 3.x）")
    print("模式：静态体检，不连数据库、不发请求。每条判定带出处。")

    # ---------------- 对照 1：术语映射 ----------------
    title("对照 1 ｜三代术语映射（官方原文口径）")
    print()
    print(f"{'1.x / 2.x 说法':<28} {'3.x 说法':<18} 说明")
    print("-" * WIDTH)
    for old, new, note in TERM_MAP:
        print(f"{old:<28} {new:<18} {note}")
    print()
    print("要点：三个概念被「压平」了两级 —— rp 并进了库，measurement 降级为表。")
    print("      v1 的 db/rp 两层命名在 3.x 只剩一层，这是后面好几条坑的总根。")

    # ---------------- 对照 2：精度矩阵 ----------------
    title("对照 2 ｜写入端点的时间戳精度支持矩阵（官方 write-data 页）")
    print()
    print(f"{'精度':<8} {'v1 /write':<14} {'v2 /api/v2/write':<20} {'v3 /api/v3/write_lp':<22}")
    print("-" * WIDTH)
    unsupported = []
    for name, v1v, v2v, v3v in PRECISION_MATRIX:
        c1 = v1v if v1v else "不支持"
        c2 = v2v if v2v else "不支持"
        c3 = v3v if v3v else "不支持"
        print(f"{name:<8} {c1:<14} {c2:<20} {c3:<22}")
        if v1v and (v2v is None or v3v is None):
            unsupported.append((name, v1v))
    print("-" * WIDTH)
    print(f"{'默认':<8} {PRECISION_DEFAULT[0]:<14} {PRECISION_DEFAULT[1]:<20} {PRECISION_DEFAULT[2]:<22}")
    print()
    print("官方原话：All timestamps are stored internally as nanoseconds.")
    print()
    print("高危项（只在 v1 端点存在，迁到 v2/v3 端点会直接失败）：")
    for name, val in unsupported:
        print(f"  precision={val:<2} -> {name}：v2 / v3 端点均不支持")
    print()
    print("自动精度检测的分档阈值（v3 默认，L4 已核实）：")
    for cond, unit, mult in AUTO_THRESHOLDS:
        print(f"  时间戳 {cond:<9} -> 判定为 {unit:<4}（乘 {mult} 转纳秒）")
    print()
    print("迁移含义：v1 端点默认纳秒，v3 端点默认 auto（猜）。")
    print("          同一批数据从 /write 换到 /api/v3/write_lp 且不显式写精度，")
    print("          解释方式就变了 —— 老脚本里那些「反正默认是纳秒」的假设全部失效。")

    # ---------------- 对照 3：清单逐条体检 ----------------
    title("对照 3 ｜迁移清单逐条体检（17 条）")
    print()
    items = build_checklist()
    print(f"{'ID':<5} {'来源':<7} {'档位':<6} 迁移项")
    print("-" * WIDTH)
    for it in items:
        flag = "  [静默]" if it.silent else ""
        print(f"{it.iid:<5} {it.src:<7} {LEVEL_LABEL[it.level]:<6} {it.what}{flag}")
    print()

    for it in items:
        print(f"--- {it.iid} [{LEVEL_LABEL[it.level]}] {it.what}")
        print(f"    来源版本：{it.src}")
        print(f"    该怎么做：{it.action}")
        if it.note:
            print(f"    备注：{it.note}")
        print(f"    出处：{it.evidence}")
        print()

    # ---------------- 对照 4：保留期语义反转专项 ----------------
    title("对照 4 ｜保留期语义反转专项（本课高危项）")
    print()
    print("先记住这一行，再往下看：")
    print(f"    2.x 的 0 = 永久保留        3.x 的 {V3_ZERO_RETENTION} = 立刻全删")
    print()
    print("「静默」还分两种，后果差一个量级，必须分开看：")
    print(f"    {KIND_LABEL['reverse']}：方向反了 —— 想永久，结果全删。灾难级。")
    print(f"    {KIND_LABEL['drift']}  ：方向没错，幅度偏了 —— 想留 91.3 天，只留 90 天。合规级。")
    print()
    cases = build_retention_cases()
    for c in cases:
        tag = f"  <== {KIND_LABEL.get(c.kind, '静默')}" if c.silent else ""
        print(f"[{c.src_ver}] 原写法：{c.src_expr}")
        print(f"        原含义：{c.src_meaning}")
        print(f"        直觉翻译：{c.naive}")
        print(f"        实际结果：{c.naive_result}{tag}")
        print(f"        正确写法：{c.correct}")
        print()
    print("翻译器自检（把上表的原写法喂给 translate_retention）：")
    for c in cases:
        if c.src_ver in ("1.x", "2.x"):
            raw = c.src_expr.split("（")[0].replace("DURATION ", "").replace("retention = ", "").strip()
            got, why = translate_retention(c.src_ver, raw)
            print(f"  {c.src_ver:<5} {raw:<14} -> {got:<14} （{why}）")

    # ---------------- 对照 5：统计与收束 ----------------
    title("对照 5 ｜统计与收束")
    print()
    stat = {LEVEL_OK: 0, LEVEL_REWRITE: 0, LEVEL_DANGER: 0}
    silent_count = 0
    for it in items:
        stat[it.level] += 1
        if it.silent:
            silent_count += 1
    total = len(items)
    print(f"清单总数：{total}")
    print(f"  直连（改个参数就能跑）      ：{stat[LEVEL_OK]} 条")
    print(f"  改写（语义在，写法要变）    ：{stat[LEVEL_REWRITE]} 条")
    print(f"  危险（照抄报错或行为相反）  ：{stat[LEVEL_DANGER]} 条")
    print(f"  其中「静默」类（不报错但反了）：{silent_count} 条（仅统计清单 M01-M17）")

    rcases = build_retention_cases()
    n_reverse = len([c for c in rcases if c.kind == "reverse"])
    n_drift = len([c for c in rcases if c.kind == "drift"])
    print()
    print(f"保留期专项另列 {len(rcases)} 个案例，其中静默 {n_reverse + n_drift} 个：")
    print(f"  {KIND_LABEL['reverse']}：{n_reverse} 个 —— 想保留结果删光（含降采样库 432 超限那个）")
    print(f"  {KIND_LABEL['drift']}  ：{n_drift} 个 —— 留是留了，但天数对不上")
    print()
    print("三句话收束：")
    print("  1. 三代之间真正不变的东西只有两样：行协议语法、时序数据的四要素。")
    print("     其余全部改过 —— 术语、端点、精度默认、保留期语义、调度机制、schema 约束。")
    print(f"  2. 17 条里 {stat[LEVEL_DANGER]} 条是危险项，其中 {silent_count} 条不报错。")
    print("     迁移失败会有人喊，迁移「成功但行为反了」没人喊 —— 后者才是要专门防的。")
    print("  3. 高危项里最贵的一个字符是 0：")
    print("     2.x 的 retention=0 是「永远保留」，3.x 的 0d 是「立刻删光」。")
    print("     它们连报错都不会给你一条。")
    print()
    print("自检（防止本脚本自己犯「嘴上说慎引、手上打满分」那类错）：")
    zero_cases = [c for c in cases if c.naive == V3_ZERO_RETENTION]
    zero_flagged = [c for c in zero_cases if c.silent]
    print(f"  保留期案例共 {len(rcases)} 条，其中直译为 {V3_ZERO_RETENTION} 的有 {len(zero_cases)} 条")
    print(f"  这 {len(zero_cases)} 条全部标记为静默危险：{len(zero_flagged) == len(zero_cases) and len(zero_cases) > 0}")
    print(f"  两类静默已分开标注（reverse={n_reverse} / drift={n_drift}）："
          f"{n_reverse > 0 and n_drift > 0}")
    print(f"  translate_retention('2.x', '0') 不返回 '0d'："
          f"{translate_retention('2.x', '0')[0] != V3_ZERO_RETENTION}")
    print()
    hr("=")


if __name__ == "__main__":
    main()
