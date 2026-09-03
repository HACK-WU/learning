# -*- coding: utf-8 -*-
"""
课 7 交付：回写四处档案（用户 2026-09-02 强制要求，缺一不可）
  1. 00-学习档案.md     —— 进度表 + 评审记录
  2. 00-评审清单.md     —— 本课勾选 + 评审记录表追加
  3. stages/3-凭什么快凭什么省/README.md —— 本课标 ✅ + 阶段收官 + 核心结论
  4. 02-课程目录.md 与 01-学习路径总览.md —— 索引链接与进度条

前车之鉴：
  - 课 5：评审记录查重用宽松子串，误命中 "- [ ]" 占位项
  - 课 6：脚本只报 WARN 未修复，课程目录链接需手动补
"""
import io
import os
import re

ROOT = "/mnt/d/projects/learning/victoriametrics"
DATE = "2026-09-02"
log = []


def read(p):
    with io.open(os.path.join(ROOT, p), encoding="utf-8") as f:
        return f.read()


def write(p, s):
    with io.open(os.path.join(ROOT, p), "w", encoding="utf-8", newline="\n") as f:
        f.write(s)


L6_TITLE = "课 6《压缩"
L7_TITLE = "课 7《内存模型与容量规划"

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
    for kw in ["缓存", "内存", "容量", "查询加速", "冷启动", "边际"]:
        if kw in ln:
            lines[i] = ln.replace("⬜", "✅")
            changed += 1
            log.append("[档案] 勾选: %s" % ln.strip()[:56])
            break
t = "\n".join(lines)

ROW7 = (
    "| {d} | {t} | 主 agent 内联（pedagogy + learner） | "
    "**P0×0 / P1×2（均已修）**。核心产出："
    "① 用「虚拟地址 vs 物理页」解释 349MB 缓存装进 119MB 进程的悖论——"
    "实测 虚拟 1490MB > 缓存统计 349MB > RSS 119MB，证明 vm_cache_size_bytes 是 fastcache 预分配的「占座」；"
    "② 用「边际成本法」推翻平均值法：写入 10005 序列、RSS 增 655360 字节 = **65.5 字节/序列**，"
    "而平均值法算出 6234.7 字节/序列，**差 95 倍**；"
    "③ 用 scanned/read=**40.08** 证明 hour_metric_ids 跳过了 **97.5%** 的数据；"
    "④ **推翻「重启会清空缓存」的常识**——两次冷启动实验（普通重启 + 删 data/cache 后重启）"
    "缓存条目均几乎不变（297415→337608；235822→235796），命中率 98.49%→99.94%，"
    "证明 fastcache 落盘于 data/cache/ 且启动时自动加载，"
    "**这修正了课 5「data/cache 目录不存在」的观察**；"
    "⑤ 实测查询耗时不对称性：序列数翻 2 倍耗时涨 3.5 倍，时间窗口翻 12 倍耗时仅涨 1.3 倍"
    "→ 优化第一优先级是减序列数而非缩窗口。"
    "P1×2 已修：补平均值/边际成本显式对照；给 `docker restart`/`rm -rf` 补安全提示。"
    "**遗留未闭环**：删除 data/cache/* 后重启，目录未自动重建，落盘触发条件不明（已在讲义坦承） | "
    "通过；P1 已落实 |"
).format(d=DATE, t=L7_TITLE)

if L7_TITLE not in t:
    lines = t.split("\n")
    idx = None
    for i, ln in enumerate(lines):
        if ln.startswith("|") and L6_TITLE in ln:
            idx = i
            break
    if idx is not None:
        end = idx
        while end + 1 < len(lines) and lines[end + 1].startswith((" ", "\t")):
            end += 1
        lines.insert(end + 1, ROW7)
        t = "\n".join(lines)
        log.append("[档案] 已追加课 7 评审记录")
    else:
        log.append("[WARN] 未找到课 6 锚点")
else:
    log.append("[档案] 课 7 记录已存在")
write(p, t)
print("  进度表勾选 %d 处" % changed)

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
    if "- [ ]" in ln and "课 7" in ln:
        lines[i] = ln.replace("- [ ]", "- [x]") + " — P0=0（%s）" % DATE
        log.append("[清单] 勾选: %s" % ln.strip()[:56])
        hit = True
        break
if not hit:
    log.append("[WARN] 清单无课 7 占位项")
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
            lines[i].startswith("|") and "课 7《" in lines[i]
            for i in range(rec_idx, last_row + 1)
        )
        if not exists:
            ROW = (
                "| {d} | {t} | 主 agent 内联（pedagogy + learner） | 0 | "
                "**推翻常识×1 + 修正前课结论×1 + 测量陷阱×2**。"
                "① 推翻「重启清空缓存」：普通重启缓存 297415→337608（不降反升）；"
                "删 data/cache 后重启 235822→235796、命中率 99.94%——fastcache 落盘于 "
                "data/cache/（metricID_tsid、metricName_tsid 等），启动时自动加载。"
                "**修正课 5「cache 目录不存在」的观察**（当时是刚启动还没落盘）。"
                "② 解决「349MB 缓存装进 119MB 进程」悖论：虚拟 1490MB > 缓存统计 349MB > RSS 119MB，"
                "vm_cache_size_bytes 是 fastcache 预分配的虚拟地址（metricIDs 恰为 64MB=2^26）。"
                "③ 推翻平均值法：边际成本 65.5 字节/序列 vs 平均值 6234.7，**差 95 倍**。"
                "④ 踩坑：hour_metric_ids 有 15 秒延迟，必须改用 /api/v1/status/tsdb 的 totalSeries。"
                "⑤ 重启会重置 vm_zstd_block_* 内存计数器（压缩比 5.648→8.494 是假象）。"
                "**P1×2 已修**：平均值/边际成本显式对照；docker restart 与 rm -rf 安全提示。"
                "learner 视角：6 个实验全部给出判据，7 条误区全部来自真实踩坑，"
                "危险操作警告齐全，未闭环疑问已诚实标注 |"
            ).format(d=DATE, t=L7_TITLE)
            lines.insert(last_row + 1, ROW)
            t = "\n".join(lines)
            log.append("[清单] 已追加课 7 评审记录")
write(p, t)

# ==================================================================
# 3. 阶段 3 概览
# ==================================================================
print("=" * 60)
print(" 3. 阶段 3 概览 README.md")
print("=" * 60)
p = "stages/3-凭什么快凭什么省/README.md"
t = read(p)
lines = t.split("\n")
for i, ln in enumerate(lines):
    if "课 7" in ln and ("⬜" in ln or "待生成" in ln or "- [ ]" in ln):
        lines[i] = ln.replace("⬜", "✅").replace("待生成", "已完成").replace("- [ ]", "- [x]")
        log.append("[概览] 课 7 标 ✅")
        break
t = "\n".join(lines)

if "阶段 3 收官" not in t and "## 核心结论" in t:
    t = t.replace(
        "## 核心结论",
        "## 阶段 3 收官：「凭什么快、凭什么省」总答案\n\n"
        "**凭什么省（课 6）**\n"
        "- 列式布局 → delta-of-delta / Gorilla XOR → ZSTD（实测 5.583 倍）\n"
        "- 每样本字节：恒定 1.02 / 缓变 3.97 / 随机 6.12\n\n"
        "**凭什么快（课 5 + 课 7）**\n"
        "- MergeSet 分层 part、TSID + 倒排索引（课 5）\n"
        "- hour_metric_ids 按小时分桶，**跳过 97.5% 数据不读**（scanned/read = 40.08）\n"
        "- fastcache 分层：tsid 命中率 99%\n"
        "- fastcache 落盘，**重启几乎不冷**\n\n"
        "**共同前提（课 4）**\n"
        "- **基数控制**。序列数翻 2 倍 → 查询耗时涨 3.5 倍；时间窗口翻 12 倍 → 耗时仅涨 1.3 倍\n\n"
        "## 核心结论",
        1,
    )
    log.append("[概览] 已补阶段 3 收官总结")
elif "65.5" not in t:
    t += (
        "\n\n## 课 7 补充\n\n"
        "- 每序列边际内存 **65.5 字节**（平均值法算出 6234.7，差 95 倍，不可用）\n"
        "- `vm_cache_size_bytes` 是虚拟地址（占座），RSS 才是物理页（真坐）\n"
        "- 内存水位 allowed/available = 0.599（60% 规则）\n"
        "- fastcache 落盘于 `data/cache/`，重启后缓存几乎不变\n"
        "- 测量教训：数序列用 `totalSeries`，看内存用 RSS，测成本用边际增量，重启后别信累计计数器\n"
    )
    log.append("[概览] 已追补课 7 核心结论")
write(p, t)

# ==================================================================
# 4. 课程目录 + 学习路径总览
# ==================================================================
print("=" * 60)
print(" 4. 课程目录 + 学习路径总览")
print("=" * 60)

L7_LINK = "stages/3-凭什么快凭什么省/7-内存模型与容量规划.md"
p = "02-课程目录.md"
t = read(p)
if L7_LINK in t:
    log.append("[目录] 课 7 链接已存在")
else:
    # 在课 6 条目后插入课 7
    lines = t.split("\n")
    for i, ln in enumerate(lines):
        if "6-压缩为什么能省7倍空间.md" in ln:
            indent = "  " if ln.startswith("  ") else ""
            # 找到课 6 的知识点子项结束位置
            j = i + 1
            while j < len(lines) and (lines[j].startswith("    -") or lines[j].strip() == ""):
                if lines[j].startswith("    -"):
                    j += 1
                else:
                    break
            block = [
                "- 课 7：[内存模型与容量规划](%s) ✅" % L7_LINK,
                "  - 知识点 1：缓存分层与内存模型",
                "  - 知识点 2：查询加速机制",
                "  - 知识点 3：冷启动与容量规划",
            ]
            lines[j:j] = block
            log.append("[目录] 已插入课 7 链接")
            break
    t = "\n".join(lines)
write(p, t)

p = "01-学习路径总览.md"
t = read(p)
if "课 5、课 6 ✅ 已完成，课 7 待生成" in t:
    t = t.replace("课 5、课 6 ✅ 已完成，课 7 待生成",
                  "课 5、课 6、课 7 ✅ 已完成（阶段 3 收官）")
    log.append("[总览] 阶段 3 标记收官")
if "12 课中已完成 6 课（课 1–6），35 知识点中已完成 20 个" in t:
    t = t.replace("12 课中已完成 6 课（课 1–6），35 知识点中已完成 20 个",
                  "12 课中已完成 7 课（课 1–7），35 知识点中已完成 23 个")
    log.append("[总览] 总进度更新为 7 课 / 23 知识点")
write(p, t)

print()
print("=" * 60)
print(" 回写结果")
print("=" * 60)
for l in log:
    print("  " + l)
