# -*- coding: utf-8 -*-
"""
课 9 交付：回写四处档案（用户 2026-09-02 强制要求，缺一不可）
  1. 00-学习档案.md
  2. 00-评审清单.md
  3. stages/4-怎么横向扩展/README.md
  4. 02-课程目录.md 与 01-学习路径总览.md

本课教训（承接课 8）：
  - 勾选必须限定在课 9 行，避免误伤其他课
  - 措辞统一用「已完成」，杜绝「✅ 未开始」这类矛盾
"""
import io
import os

ROOT = "/mnt/d/projects/learning/victoriametrics"
DATE = "2026-09-02"
L8_TITLE = "课 8《集群三件套与最小集群实战"
L9_TITLE = "课 9《复制、去重与高可用"
log = []


def read(p):
    with io.open(os.path.join(ROOT, p), encoding="utf-8") as f:
        return f.read()


def write(p, s):
    with io.open(os.path.join(ROOT, p), "w", encoding="utf-8", newline="\n") as f:
        f.write(s)


# ==================================================================
# 1. 00-学习档案.md
# ==================================================================
print("=" * 60)
print(" 1. 00-学习档案.md")
print("=" * 60)
p = "00-学习档案.md"
t = read(p)
lines = t.split("\n")
changed = 0
for i, ln in enumerate(lines):
    if not (ln.strip().startswith("|") and "⬜" in ln):
        continue
    if "课 9" not in ln:          # 精确限定课 9
        continue
    lines[i] = ln.replace("⬜", "✅")
    changed += 1
    log.append("[档案] 勾选: %s" % ln.strip()[:60])
t = "\n".join(lines)

ROW9 = (
    "| {d} | {t} | 主 agent 内联（pedagogy + learner） | "
    "**P0×0 / P1×0 / P2×1（已修复）**。"
    "核心产出："
    "① 揭示**副本必须配 dedup**——RF=2 后无 dedup 查询结果 **600**（翻倍），"
    "配 dedup 后 **300**（正确），vmselect 完全不知情副本的存在；"
    "② 踩出** dedup 间隔误删陷阱**：12 个样本（间隔 5s）用 `dedup=30s` "
    "只剩 **3 个**（丢 75%），改用 `dedup=5s` 恢复 12 个——"
    "证明间隔必须**等于**真实采集间隔，设大不会漏掉副本只会误删数据；"
    "③ 验证**高可用成立**：停掉一个 vmstorage，有副本+dedup 时结果保持 **300 不变**，"
    "与课 8 无副本的 **1000→509** 形成决定性对照；"
    "④ 发现**副本缺口不自动补齐**（本课最重要警告）：故障期写入 100 条，"
    "节点恢复后 vmstorage1=100 / vmstorage2=**0**，社区版无副本修复机制，"
    "且无内置方式查询哪些数据缺副本；"
    "⑤ 抓到副本失败的**唯一可靠证据**——日志 "
    "`cannot make a copy #2 out of 2 copies ... temporarily unavailable`，"
    "写入仍返回 **HTTP 204**；并发现指标 "
    "`vm_rpc_rows_incompletely_replicated_total` 在 5 次失败后**仍为 0**，可靠性存疑；"
    "⑥ 揭示 **RF>1 会禁用慢节点重路由**（启动日志明确警告），"
    "一个慢节点会拖慢整体写入；"
    "⑦ 验证**无状态组件高可用**：第二个 vminsert(8488) 在第一个停止后仍可写入 HTTP 204；"
    "⑧ 给出**最小推荐配置：3 个 vmstorage 配 RF=2**——2 节点配 RF=2 时"
    "故障期数据会退化成单副本。"
    "另修正 1 处 P2：`shared-nothing` 补上「互不相识、互不通信」解释 | "
    "通过；无阻塞项 |"
).format(d=DATE, t=L9_TITLE)

if L9_TITLE not in t:
    lines = t.split("\n")
    idx = None
    for i, ln in enumerate(lines):
        if ln.startswith("|") and L8_TITLE in ln:
            idx = i
            break
    if idx is not None:
        end = idx
        while end + 1 < len(lines) and lines[end + 1].startswith((" ", "\t")):
            end += 1
        lines.insert(end + 1, ROW9)
        t = "\n".join(lines)
        log.append("[档案] 已追加课 9 评审记录")
    else:
        log.append("[WARN] 未找到课 8 锚点，评审记录未追加")
else:
    log.append("[档案] 课 9 记录已存在")
write(p, t)
print("  进度表勾选 %d 处（仅课 9 行）" % changed)

# ==================================================================
# 2. 00-评审清单.md
# ==================================================================
print("=" * 60)
print(" 2. 00-评审清单.md")
print("=" * 60)
p = "00-评审清单.md"
t = read(p)
lines = t.split("\n")
hit = False
for i, ln in enumerate(lines):
    if "- [ ]" in ln and "课 9" in ln:
        lines[i] = ln.replace("- [ ]", "- [x]") + " — P0=0（%s）" % DATE
        log.append("[清单] 勾选: %s" % ln.strip()[:60])
        hit = True
        break
if not hit:
    log.append("[WARN] 清单无课 9 占位项")
t = "\n".join(lines)

rec_idx = None
for i, ln in enumerate(lines):
    if ln.strip().startswith("## 评审记录"):
        rec_idx = i
        break
if rec_idx is not None:
    last_row = None
    for i in range(rec_idx, len(lines)):
        if lines[i].startswith("|"):
            last_row = i
        elif last_row is not None and lines[i].strip() == "":
            break
    if last_row is not None:
        exists = any(
            lines[i].startswith("|") and "课 9《" in lines[i]
            for i in range(rec_idx, last_row + 1)
        )
        if not exists:
            ROW = (
                "| {d} | {t} | 主 agent 内联（pedagogy + learner） | 0 | "
                "**7 组实验全部真跑，均给出判据**。"
                "① 副本必配 dedup：无 dedup 600 / 有 dedup 300。"
                "② dedup 误删实测：12 个样本（间隔 5s）用 30s 窗口只剩 3 个，"
                "改用 5s 恢复 12 个——本课最有价值的踩坑。"
                "③ 高可用对照：停节点后有副本+dedup 保持 300，"
                "对比课 8 无副本的 1000→509。"
                "④ **副本缺口不补齐**（最重要警告）：故障期 100 条数据恢复后仍是 100/0。"
                "⑤ 副本失败只在日志留痕（`cannot make a copy`），"
                "HTTP 仍返 204；指标 `vm_rpc_rows_incompletely_replicated_total` "
                "在 5 次失败后仍为 0，可靠性存疑（已作为未闭环疑问留存）。"
                "⑥ RF>1 禁用慢节点重路由（启动日志警告）。"
                "⑦ 多 vminsert：停一个，另一个仍 204。"
                "⑧ 最小推荐 3 节点配 RF=2。"
                "Agent B 报 P1×1（副本缺口）+ P2×1（shared-nothing 缺解释）："
                "P1 经核验为**误判**（误区第 5 条标题即为"
                "「以为节点恢复后副本会自动补齐」，内容完整，"
                "检测关键词『不自动补齐』与实际措辞『不会自动补齐』不匹配）；"
                "P2 为**真缺陷已修复**，补上「互不相识、互不通信」解释 |"
            ).format(d=DATE, t=L9_TITLE)
            lines.insert(last_row + 1, ROW)
            t = "\n".join(lines)
            log.append("[清单] 已追加课 9 评审记录")
write(p, t)

# ==================================================================
# 3. 阶段 4 概览
# ==================================================================
print("=" * 60)
print(" 3. 阶段 4 概览 README.md")
print("=" * 60)
p = "stages/4-怎么横向扩展/README.md"
t = read(p)

OLD = "### 课 9：复制、去重与高可用 ⬜ 未开始"
NEW = (
    "### 课 9：复制、去重与高可用 ✅ 已完成（%s）\n\n"
    "- 知识点 1：复制因子与容量代价\n"
    "- 知识点 2：去重机制\n"
    "- 知识点 3：高可用部署与故障演练" % DATE
)
if OLD in t:
    t = t.replace(OLD, NEW)
    log.append("[概览] 课 9 标 ✅ 并补知识点")
elif "课 9：复制、去重与高可用 ✅" in t:
    log.append("[概览] 课 9 已标 ✅")
else:
    log.append("[WARN] 概览未匹配到课 9 条目")

# 追加课 9 核心结论
ANCHOR = "### 课 8 已验证"
L9_CONCL = (
    "### 课 9 已验证\n\n"
    "- **副本必配 dedup**：RF=2 后无 dedup 聚合 = **600**（翻倍），配 dedup = **300**（正确）\n"
    "- **dedup 间隔 = 采集间隔**：12 个样本（间隔 5s）用 `dedup=30s` 只剩 **3 个**；"
    "`dedup=5s` 恢复 12 个\n"
    "- **高可用成立**：停一节点，有副本+dedup 结果保持 **300 不变**"
    "（对比课 8 无副本的 **1000→509**）\n"
    "- **⚠️ 副本缺口不自动补齐**：故障期写 100 条，节点恢复后仍是 **100 / 0**\n"
    "- **⚠️ 副本失败只留日志**：HTTP 仍返 204；"
    "指标 `vm_rpc_rows_incompletely_replicated_total` 5 次失败后**仍为 0**，可靠性存疑\n"
    "- **⚠️ RF>1 禁用慢节点重路由**：启动日志明确警告，慢节点会拖慢整体写入\n"
    "- **最小推荐配置**：**3 个 vmstorage 配 RF=2**（2 节点配 RF=2 故障期会退化成单副本）\n\n"
)
if "### 课 9 已验证" not in t:
    if ANCHOR in t:
        t = t.replace(ANCHOR, L9_CONCL + ANCHOR, 1)
        log.append("[概览] 已追加课 9 核心结论")
    else:
        log.append("[WARN] 概览未找到锚点")
write(p, t)

# ==================================================================
# 4. 课程目录 + 学习路径总览
# ==================================================================
print("=" * 60)
print(" 4. 课程目录 + 学习路径总览")
print("=" * 60)

L9_LINK = "stages/4-怎么横向扩展/9-复制去重与高可用.md"
p = "02-课程目录.md"
t = read(p)
if L9_LINK in t:
    log.append("[目录] 课 9 链接已存在")
else:
    lines = t.split("\n")
    done = False
    for i, ln in enumerate(lines):
        if ln.strip() == "- 课 9：复制、去重与高可用":
            lines[i] = (
                "- 课 9：[复制、去重与高可用](%s) ✅\n"
                "  - 知识点 1：复制因子与容量代价\n"
                "  - 知识点 2：去重机制\n"
                "  - 知识点 3：高可用部署与故障演练" % L9_LINK
            )
            log.append("[目录] 已插入课 9 链接 + 知识点")
            done = True
            break
    if not done:
        log.append("[WARN] 目录未找到课 9 条目")
    t = "\n".join(lines)
write(p, t)

p = "01-学习路径总览.md"
t = read(p)
before = t
if "12 课中已完成 8 课（课 1–8），35 知识点中已完成 28 个" in t:
    t = t.replace("12 课中已完成 8 课（课 1–8），35 知识点中已完成 28 个",
                  "12 课中已完成 9 课（课 1–9），35 知识点中已完成 31 个")
    log.append("[总览] 总进度更新为 9 课 / 31 知识点")
elif "已完成 8 课" in t:
    import re as _re
    t = _re.sub(r"已完成 8 课（课 1–8）", "已完成 9 课（课 1–9）", t)
    t = _re.sub(r"35 知识点中已完成 \d+ 个", "35 知识点中已完成 31 个", t)
    log.append("[总览] 总进度更新（正则兜底）")
if t != before:
    write(p, t)
else:
    log.append("[总览] 未匹配到进度字符串，需人工检查")

print()
print("=" * 60)
print(" 回写结果")
print("=" * 60)
for l in log:
    print("  " + l)
