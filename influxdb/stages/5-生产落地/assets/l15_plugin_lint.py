# -*- coding: utf-8 -*-
"""
第 15 课 实验 B：插件代码静态检查器（可接 CI 的 pre-commit 门禁）
==========================================================================
目的：把本课讲的「插件六条铁律」变成**可自动执行的检查**，
      在插件被 create trigger 之前就把高危写法拦下来。

纯标准库，不依赖 Docker，不依赖 InfluxDB —— 直接对 .py 文件做静态分析，
可挂进 CI / pre-commit，也可以本地自查。

实现思路：**故意不 import 插件代码**（插件文件里用到 influxdb3_local /
LineBuilder 这些运行时注入的符号，本地 import 必然 NameError），
而是用 ast 解析语法树 + 正则做源码扫描。

--------------------------------------------------------------------------
六条检查项（前 3 条基于官方 API reference 明文，后 3 条是工程实践）
--------------------------------------------------------------------------
P0-1  循环写回风险：插件里存在写调用，且没有「跳过某张表/某个库」的防护
P0-2  参数化查询：SQL 里用 f-string / % / .format() 拼字符串（注入风险）
P0-3  裸 except Exception 兜住插件取消信号（官方明文：取消时抛的是
      KeyboardInterrupt，它是 BaseException 子类，不该被 except Exception 吞掉）
P1-1  监听 all_tables 却没有任何表过滤逻辑
P1-2  插件入口函数签名与 trigger-spec 不匹配
P2-1  过度日志（在高频 WAL 插件里逐行 info，86,400 次/天 × 每行一条）
"""

import ast
import re
import sys
import os

# 官方 API reference 明文的写方法
WRITE_METHODS = ("write", "write_to_db", "write_sync", "write_sync_to_db")

# 官方 API reference 明文的三个入口函数
ENTRYPOINTS = {
    "process_writes": "table:TABLE / all_tables（WAL 写入触发）",
    "process_scheduled_call": "every:DURATION / cron:EXPR（定时触发）",
    "process_request": "request:PATH（HTTP 请求触发）",
}

SEV_ORDER = {"P0": 0, "P1": 1, "P2": 2}


def rule_p1_entrypoint(src, tree, findings):
    """P1-2：入口函数签名与 trigger-spec 是否匹配。"""
    defined = [n.name for n in tree.body
               if isinstance(n, ast.FunctionDef) and n.name in ENTRYPOINTS]

    if not defined:
        findings.append((
            "P0", "P1-2", "入口函数",
            "文件里找不到任何入口函数（process_writes / "
            "process_scheduled_call / process_request）",
            "官方 API reference 明文：插件必须定义与 trigger 类型匹配的入口函数",
        ))
        return

    for name in defined:
        fn = next(n for n in tree.body
                  if isinstance(n, ast.FunctionDef) and n.name == name)
        argc = len(fn.args.args)
        # 官方签名：process_writes(3) / process_scheduled_call(3) / process_request(5)
        expect = {"process_writes": 3,
                  "process_scheduled_call": 3,
                  "process_request": 5}[name]
        if argc < expect:
            findings.append((
                "P0", "P1-2", f"入口函数 {name}",
                f"形参只有 {argc} 个，官方签名要求 {expect} 个 "
                f"（{name} 的官方签名见 API reference）",
                "参数个数不足会在运行时直接 TypeError，触发器一启用就报错",
            ))

    print(f"   入口函数签名：找到 {len(defined)} 个 → {', '.join(defined)}")
    print(f"   对应 trigger-spec：{ENTRYPOINTS[defined[0]]}")


def rule_p2_loopback(src, tree, findings):
    """P0-1：写回循环风险（本课实验 A 对照 4 的根因）。"""
    has_write = any(re.search(r"\." + m + r"\s*\(", src) for m in WRITE_METHODS)

    # 官方示例的防护写法：比对 table_name 后 continue / return
    guard_table = bool(re.search(
        r"table_batch\s*\[\s*['\"]table_name['\"]\s*\]", src))
    guard_flow = bool(re.search(r"\b(continue|return)\b", src))
    guarded = guard_table and guard_flow

    print(f"   存在写调用：{'是' if has_write else '否'}"
          f" ｜ 表级防护（比对 table_name + continue/return）："
          f"{'有' if guarded else '无'}")

    if has_write and not guarded:
        findings.append((
            "P0", "P0-1", "循环写回",
            "插件会写回数据，但没有任何「跳过某张表」的防护",
            "若 trigger-spec 是 all_tables 且写回同一张表 → 每秒翻倍，"
            "15 秒破百万、20 秒破 5,000 万行/秒（实验 A 对照 4）；"
            "改成 --trigger-spec \"table:源表\" 或在插件开头 continue 掉目标表",
        ))
    elif has_write and guarded:
        print("   ✅ 已有表级防护，循环写回风险已规避")
    else:
        print("   ✅ 无写调用，不存在循环写回风险")


def rule_p3_sql_injection(src, tree, findings):
    """P0-2：SQL 字符串拼接（注入风险）。"""
    hits = []

    for node in ast.walk(tree):
        # f-string：JoinedStr 且含 FormattedValue
        if isinstance(node, ast.JoinedStr) and any(
                isinstance(v, ast.FormattedValue) for v in node.values):
            seg = ast.get_source_segment(src, node) or ""
            if re.search(r"\b(SELECT|INSERT|DELETE|DROP|UPDATE)\b", seg, re.I):
                hits.append(("f-string 拼接 SQL", seg.strip()[:70]))
        # % 格式化
        if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Mod):
            seg = ast.get_source_segment(src, node) or ""
            if re.search(r"\b(SELECT|INSERT|DELETE|DROP|UPDATE)\b", seg, re.I):
                hits.append(("% 格式化拼接 SQL", seg.strip()[:70]))
        # .format()
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) \
                and node.func.attr == "format":
            seg = ast.get_source_segment(src, node) or ""
            if re.search(r"\b(SELECT|INSERT|DELETE|DROP|UPDATE)\b", seg, re.I):
                hits.append((".format() 拼接 SQL", seg.strip()[:70]))

    print(f"   拼接式 SQL：{len(hits)} 处")

    for kind, seg in hits:
        findings.append((
            "P0", "P0-2", "SQL 注入",
            f"{kind}：{seg}",
            "官方 API reference 明文支持参数化："
            "query(sql, {\"host\": \"host1\"})，SQL 里用 $host 占位，"
            "且参数值必须是字符串（传 int/float 会 raise TypeError）",
        ))

    if not hits:
        print("   ✅ 未发现拼接式 SQL")


def rule_p4_broad_except(src, tree, findings):
    """P0-3：裸 except Exception 会吞掉插件取消信号。"""
    broad = []
    for node in ast.walk(tree):
        if isinstance(node, ast.ExceptHandler) and node.type is not None:
            seg = ast.get_source_segment(src, node) or ""
            if re.match(r"except\s+Exception", seg):
                broad.append(seg.split("\n")[0].strip())

    print(f"   except Exception 出现次数：{len(broad)}")

    if broad:
        findings.append((
            "P0", "P0-3", "异常吞噬",
            f"存在 {len(broad)} 处 except Exception",
            "官方 API reference 明文：插件被取消时（服务器关闭 / 触发器被禁用或删除）"
            "，logging、write、query 方法会抛 KeyboardInterrupt，"
            "它是 BaseException 子类而不是 Exception，"
            "所以 except Exception 不该吞掉它 —— "
            "但如果你在 except Exception 里做了「吞掉异常继续跑」的处理，"
            "长循环就无法优雅退出；"
            "要区分错误类型请用 except Exception as err: "
            "type(err).__name__ == 'QueryError'",
        ))
    else:
        print("   ✅ 无 except Exception，取消信号可正常上抛")


def rule_p5_all_tables(src, tree, findings):
    """P1-1：all_tables 监听缺过滤。"""
    uses_all_tables = bool(re.search(r"all_tables", src))
    has_filter = bool(re.search(
        r"\b(continue|return|exclude|skip|if\s+table_name)", src))

    print(f"   代码内提及 all_tables：{'是' if uses_all_tables else '否'}"
          f" ｜ 有表过滤逻辑：{'有' if has_filter else '无'}")

    if uses_all_tables and not has_filter:
        findings.append((
            "P1", "P1-1", "监听范围",
            "代码涉及 all_tables 但没有表过滤逻辑",
            "all_tables 会收到库里每一张表的写入，包括插件自己写回的表与系统表；"
            "要么改用 --trigger-spec \"table:表名\"，"
            "要么用 --trigger-arguments exclude_tables=a,b,c 并在插件里过滤",
        ))


def _is_rows_subscript(node):
    """判断 for 语句的迭代对象是否为 table_batch["rows"]。"""
    it = node.iter
    if not isinstance(it, ast.Subscript):
        return False
    # 下标必须是字符串常量 "rows"
    sl = it.slice
    if not (isinstance(sl, ast.Constant) and sl.value == "rows"):
        return False
    # 被下标的对象必须名为 table_batch
    v = it.value
    return isinstance(v, ast.Name) and v.id == "table_batch"


def _calls_log(node):
    """在节点子树里找 info/warn/error 调用，返回方法名集合。"""
    found = set()
    for sub in ast.walk(node):
        if isinstance(sub, ast.Call) and isinstance(sub.func, ast.Attribute):
            if sub.func.attr in ("info", "warn", "error"):
                found.add(sub.func.attr)
    return found


def rule_p6_log_volume(src, tree, findings):
    """P2-1：WAL 插件里的逐行日志（只看 row 循环**体内**的日志调用）。"""
    is_wal = any(isinstance(n, ast.FunctionDef) and n.name == "process_writes"
                 for n in tree.body)

    offenders = []
    for node in ast.walk(tree):
        if isinstance(node, ast.For) and _is_rows_subscript(node):
            # 只看循环体本身，不含循环之后的同级语句
            for stmt in node.body:
                logs = _calls_log(stmt)
                if logs:
                    offenders.append(sorted(logs))

    log_in_loop = bool(offenders)

    print(f"   是 WAL 插件：{'是' if is_wal else '否'}"
          f" ｜ 逐行循环体内打日志：{'是' if log_in_loop else '否'}")

    if is_wal and log_in_loop:
        names = sorted({n for grp in offenders for n in grp})
        findings.append((
            "P2", "P2-1", "日志风暴",
            f"WAL 插件在「逐行循环体内」调用了 {', '.join(names)}",
            "WAL 触发器每秒一次 = 86,400 次/天（实验 A 对照 1）；"
            "若每批 N 行就打 N 条，日志表会以每秒 N 行的速度膨胀，"
            "且每条日志都要写 _internal 库 —— 只打汇总（每批一条），不打逐行",
        ))
    elif is_wal:
        print("   ✅ 日志只打在循环之外（汇总级），无日志风暴风险")


def check_file(path):
    with open(path, "r", encoding="utf-8") as f:
        src = f.read()

    print()
    print("=" * 80)
    print(f" 检查文件：{os.path.basename(path)}")
    print("=" * 80)

    try:
        tree = ast.parse(src)
    except SyntaxError as e:
        print(f" ❌ 语法错误，无法解析：{e}")
        return []

    findings = []
    rule_p1_entrypoint(src, tree, findings)
    rule_p2_loopback(src, tree, findings)
    rule_p3_sql_injection(src, tree, findings)
    rule_p4_broad_except(src, tree, findings)
    rule_p5_all_tables(src, tree, findings)
    rule_p6_log_volume(src, tree, findings)

    print()
    if findings:
        findings.sort(key=lambda x: SEV_ORDER[x[0]])
        print(f" ⚠️ 发现 {len(findings)} 个问题：")
        print()
        for sev, code, cat, desc, fix in findings:
            print(f"   [{sev}] {code} · {cat}")
            print(f"        问题：{desc}")
            print(f"        依据/改法：{fix}")
            print()
    else:
        print(" ✅ 六项检查全部通过")

    return findings


# ---------------------------------------------------------------- 演示样例
BAD_PLUGIN = '''\
# bad_plugin.py —— 反面教材：六条里踩了四条
def process_writes(influxdb3_local, table_batches, args=None):
    for table_batch in table_batches:
        for row in table_batch["rows"]:
            host = row["tags"]["host"]
            q = f"SELECT * FROM cpu WHERE host = '{host}'"   # P0-2
            try:
                r = influxdb3_local.query(q)                  # 拼接 SQL
                line = LineBuilder("cpu_alerts")
                line.tag("host", host).float64_field("v", 1.0)
                influxdb3_local.write(line)                   # P0-1 无防护
                influxdb3_local.info("row done", row)          # P2-1 逐行日志
            except Exception:                                  # P0-3
                pass
'''

GOOD_PLUGIN = '''\
# good_plugin.py —— 正面教材：六条全过
def process_writes(influxdb3_local, table_batches, args=None):
    threshold = float(args.get("threshold", "90")) if args else 90.0

    for table_batch in table_batches:
        # 防护一：跳过自己要写回的表（防递归）
        if table_batch["table_name"] == "cpu_alerts":
            continue

        hits = 0
        for row in table_batch["rows"]:
            host = row["tags"].get("host")
            usage = row["fields"].get("usage_percent")
            if host is None or usage is None:
                continue
            if usage <= threshold:
                continue

            # 防护二：参数化查询，值必须是字符串
            detail = influxdb3_local.query(
                "SELECT * FROM cpu WHERE host = $host",
                {"host": str(host)},
            )
            line = LineBuilder("cpu_alerts")
            line.tag("host", str(host)).float64_field("usage", float(usage))
            influxdb3_local.write(line)
            hits += 1

        # 防护三：只打汇总，不打逐行
        if hits:
            influxdb3_local.info(f"cpu_alerts written: {hits}")
'''


def demo():
    print()
    print("*" * 80)
    print(" 演示模式：对两段内置样例代码跑检查（坏例子 vs 好例子）")
    print("*" * 80)

    import tempfile
    tmp = tempfile.gettempdir()
    bad = os.path.join(tmp, "l15_bad_plugin.py")
    good = os.path.join(tmp, "l15_good_plugin.py")
    with open(bad, "w", encoding="utf-8") as f:
        f.write(BAD_PLUGIN)
    with open(good, "w", encoding="utf-8") as f:
        f.write(GOOD_PLUGIN)

    print()
    print("#" * 80)
    print("# 第一段：反面教材（把常见错误集中在一处）")
    print("#" * 80)
    check_file(bad)

    print()
    print("#" * 80)
    print("# 第二段：正面教材（同一需求的正确写法）")
    print("#" * 80)
    check_file(good)

    print()
    print("=" * 80)
    print(" 怎么用在你自己的插件上")
    print("=" * 80)
    print("   python l15_plugin_lint.py 你的插件.py [更多插件.py ...]")
    print()
    print(" 建议挂进 CI：只要输出里有 [P0] 就让流水线失败。")
    print(" 注意：这是**启发式**检查（ast + 正则），不是类型检查器，")
    print(" 会有漏报与误报；它的价值是把「六条铁律」变成可执行的门禁，")
    print(" 而不是替代人工评审。")


def main():
    if len(sys.argv) > 1:
        total = 0
        p0 = 0
        for p in sys.argv[1:]:
            findings = check_file(p)
            total += len(findings)
            p0 += sum(1 for f in findings if f[0] == "P0")
        print()
        print("=" * 80)
        print(f" 合计：{total} 个问题（其中 P0 {p0} 个）")
        print("=" * 80)
        sys.exit(1 if p0 else 0)
    else:
        demo()


if __name__ == "__main__":
    main()
