# -*- coding: utf-8 -*-
"""
课 5 交付收尾：向 00-学习档案.md 的「评审记录」表追加课 5 记录。

与 00-评审清单.md 的分工：
    - 评审清单：管待办勾选（- [x]）+ 评审记录表（详细评审意见）
    - 学习档案：管进度表 + 评审记录表（结论摘要，一句话带过）

两者都要写，缺一不可（用户 2026-09-02 明确要求回写四处档案）。
"""
import io
import sys

F = "/mnt/d/projects/learning/victoriametrics/00-学习档案.md"
DATE = "2026-09-02"

ANCHOR = (
    "| 2026-09-02 | 多阶段大纲 | 主 agent 内联（pedagogy） | "
)

ROW = (
    "| {d} | 课 4《写入协议全家桶与基数治理》 | 主 agent 内联（pedagogy + learner） | "
    "**P0×0**。实测推翻直觉×2：Influx line protocol 的字段名一律拼进指标名（后缀非单位标识符）；"
    "CSV import 返回 HTTP 204 却一行未写入 → 确立「验证写入看 `vm_rows_inserted_total`，不看状态码」判据。"
    "P1×2 已修：metric_relabel 误判（对比基准选错）、OpenTSDB 端口冲突 | 通过；P1 已在落盘时落实 |\n"
    "| {d} | 课 5《存储引擎：MergeSet 与磁盘结构》 | 主 agent 内联（pedagogy + learner） | "
    "**P0×0**。重大反直觉发现：**`items.bin`（806 KB）> `values.bin`（285 KB）——索引比数据还占地方**，"
    "推翻「压缩率高=算法强」的直觉，把省存储的真正杠杆指回基数治理。"
    "另修正 `indexdb/` 路径认知（在 `data/` 下，非顶层）。"
    "P1×2 已修：容器内/宿主机路径视角混用（补对照表）、文件统计是快照非静态值（补变化说明）。"
    "P2×2 已修：繁体「本課」6 处转简体；补 stage 3 概览 README 使导航可达。"
    "learner 视角：counter 四轮排查提炼可迁移方法论"
    "——**遇到 counter 与预期不符，先做静默基线实验**（静默 30s 自涨 2，证明是 self-scrape 噪声） | "
    "通过；P1/P2 已在落盘时落实 |"
).format(d=DATE)

with io.open(F, encoding="utf-8") as f:
    text = f.read()

# 幂等检查：档案里是否已有课 5 评审记录
if "| 课 5《存储引擎" in text:
    print("[SKIP] 学习档案已含课 5 评审记录，跳过")
    sys.exit(0)

if "| 课 4《写入协议" in text:
    print("[SKIP] 学习档案已含课 4 评审记录，跳过课 4，仅追加课 5")
    # 只追加课 5 那一行：插入到课 4 行之后
    lines = text.split("\n")
    idx = None
    for i, ln in enumerate(lines):
        if ln.startswith("|") and "| 课 4《写入协议" in ln:
            idx = i
            break
    if idx is None:
        print("[FAIL] 找到课 4 标记但定位不到行")
        sys.exit(1)
    l5_only = ROW.split("\n")[1]
    lines.insert(idx + 1, l5_only)
    text = "\n".join(lines)
    added = 1
else:
    # 课 4、课 5 都没有 → 插入到大纲评审行之后
    if ANCHOR not in text:
        print("[FAIL] 未找到大纲评审记录锚点")
        sys.exit(1)
    lines = text.split("\n")
    idx = None
    for i, ln in enumerate(lines):
        if ln.startswith(ANCHOR):
            idx = i
            break
    # 大纲记录可能跨多行，找到该记录结束（下一行是 | 开头或空行）
    end = idx
    while end + 1 < len(lines) and (lines[end + 1].startswith(" ") or lines[end + 1].startswith("\t")):
        end += 1
    for r in reversed(ROW.split("\n")):
        lines.insert(end + 1, r)
    text = "\n".join(lines)
    added = 2

with io.open(F, "w", encoding="utf-8", newline="\n") as f:
    f.write(text)

print("[OK] 已向学习档案评审记录表追加 %d 条记录" % added)
