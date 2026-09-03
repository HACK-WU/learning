# -*- coding: utf-8 -*-
"""
课 6 交付：回写四处档案（用户 2026-09-02 强制要求，缺一不可）
  1. 00-学习档案.md     —— 进度表 + 评审记录
  2. 00-评审清单.md     —— 本课勾选 + 评审记录表追加
  3. stages/3-凭什么快凭什么省/README.md —— 本课标 ✅ + 阶段状态 + 核心结论
  4. 02-课程目录.md 与 01-学习路径总览.md —— 索引链接与进度条

前车之鉴（课 5 教训）：
  - 评审记录查重不能用宽松子串（会命中 "- [ ]" 占位项导致误判跳过）
  - 必须用「评审记录表末行」作精确锚点
"""
import io
import os
import sys

ROOT = "/mnt/d/projects/learning/victoriametrics"
DATE = "2026-09-02"
log = []


def read(p):
    with io.open(os.path.join(ROOT, p), encoding="utf-8") as f:
        return f.read()


def write(p, s):
    with io.open(os.path.join(ROOT, p), "w", encoding="utf-8", newline="\n") as f:
        f.write(s)


# ==================================================================
# 1. 00-学习档案.md —— 进度表 + 评审记录
# ==================================================================
print("=" * 60)
print(" 1. 00-学习档案.md")
print("=" * 60)
p = "00-学习档案.md"
t = read(p)
lines = t.split("\n")

# 1a. 进度表：找到课 6 的三行，标 ✅
L6_TITLES = [
    "列式布局",
    "压缩算法",
    "降采样",
]
changed = 0
for i, ln in enumerate(lines):
    if ln.strip().startswith("|") and ("课 6" in ln or "6《" in ln or "课6" in ln):
        # 找出课 6 的知识点行
        pass

# 更稳的做法：定位阶段 3 进度表中课 6 的行
for i, ln in enumerate(lines):
    if "压缩" in ln and ln.strip().startswith("|") and "⬜" in ln:
        lines[i] = ln.replace("⬜", "✅")
        changed += 1
        log.append("[档案] 进度表勾选: %s" % ln.strip()[:60])
    elif "列式" in ln and ln.strip().startswith("|") and "⬜" in ln:
        lines[i] = ln.replace("⬜", "✅")
        changed += 1
        log.append("[档案] 进度表勾选: %s" % ln.strip()[:60])
    elif "降采样" in ln and ln.strip().startswith("|") and "⬜" in ln:
        lines[i] = ln.replace("⬜", "✅")
        changed += 1
        log.append("[档案] 进度表勾选: %s" % ln.strip()[:60])

t = "\n".join(lines)

# 1b. 评审记录表：追加课 6 记录
ANCHOR_L5 = "| 课 5《存储引擎"
if "| 课 6《压缩" not in t:
    ROW = (
        "| {d} | 课 6《压缩：为什么能省 7 倍空间》 | 主 agent 内联（pedagogy + learner） | "
        "**P0×0**。核心产出：用「三组样本数相同、值形态不同」的对照实验，"
        "证明压缩存在**前置编码层**——三组交给 ZSTD 的原始字节为 266383/938997/1463618（差 5.5 倍），"
        "若直接喂 float64 则应完全相同。实测每样本字节：恒定 1.02 / 缓变 3.97 / 随机 6.12。"
        "回答课 5 伏笔（115.7 行≈463 字节）。"
        "**测量方法论踩坑×3 已全部写入讲义**：① 磁盘增量法被后台合并干扰（改用 ZSTD 计数增量）；"
        "② 用 NOW+正数 生成时间戳导致数据落在未来查不到（改用 NOW-1200）；"
        "③ `vm_rows` 是累计计数，不能当存量（改用 count_over_time）。"
        "P1×2 已修：补两处「类比失效的边界」（知识点 2、3）、"
        "补课 5 遗留的 115.7 行伏笔正面回答 | "
        "通过；P1 已在落盘时落实 |"
    ).format(d=DATE)
    lines = t.split("\n")
    idx = None
    for i, ln in enumerate(lines):
        if ln.startswith("|") and ANCHOR_L5 in ln:
            idx = i
            break
    if idx is not None:
        # 课 5 记录可能跨行，找到结束
        end = idx
        while end + 1 < len(lines) and lines[end + 1].startswith((" ", "\t")):
            end += 1
        lines.insert(end + 1, ROW)
        t = "\n".join(lines)
        log.append("[档案] 已追加课 6 评审记录")
    else:
        log.append("[WARN] 未找到课 5 评审锚点，课 6 记录未追加")
else:
    log.append("[档案] 课 6 评审记录已存在，跳过")

write(p, t)
print("  进度表勾选 %d 处" % changed)

# ==================================================================
# 2. 00-评审清单.md —— 勾选 + 评审记录
# ==================================================================
print("=" * 60)
print(" 2. 00-评审清单.md")
print("=" * 60)
p = "00-评审清单.md"
t = read(p)

L6_ITEM = "阶段 3·课 6《压缩：为什么能省 7 倍空间》"
OLD = "- [ ] %s — pedagogy + learner 双视角" % L6_ITEM
NEW = "- [x] %s — pedagogy + learner 双视角 — P0=0（%s）" % (L6_ITEM, DATE)
if OLD in t:
    t = t.replace(OLD, NEW)
    log.append("[清单] 已勾选课 6 占位项")
elif NEW in t:
    log.append("[清单] 课 6 占位项已勾选")
else:
    # 可能清单里还没这项，尝试宽松匹配
    found = False
    for ln in t.split("\n"):
        if "- [ ]" in ln and "课 6" in ln and "pedagogy" in ln:
            t = t.replace(ln, ln.replace("- [ ]", "- [x]") + " — P0=0（%s）" % DATE)
            log.append("[清单] 已勾选课 6（宽松匹配）: %s" % ln.strip()[:60])
            found = True
            break
    if not found:
        log.append("[WARN] 清单中未找到课 6 占位项，需手动添加")

# 追加评审记录到评审记录表末行
rec_hdr = None
lines = t.split("\n")
for i, ln in enumerate(lines):
    if ln.strip().startswith("## 评审记录"):
        rec_hdr = i
        break
if rec_hdr is not None:
    last_row = None
    for i in range(rec_hdr, len(lines)):
        if lines[i].startswith("|"):
            last_row = i
        elif last_row is not None and lines[i].strip() == "":
            break
    if last_row is not None:
        exists = any(
            lines[i].startswith("|") and "| 课 6《" in lines[i]
            for i in range(rec_hdr, last_row + 1)
        )
        if not exists:
            ROW = (
                "| {d} | 课 6《压缩：为什么能省 7 倍空间》 | 主 agent 内联（pedagogy + learner） | 0 | "
                "**实测推翻直觉×1 + 测量方法论踩坑×3**。"
                "① 直觉以为「59 倍压缩 = ZSTD 很神」，实测 ZSTD 只有 5.583 倍，"
                "差额来自前两层（列式布局 + 值编码）——用三组对照实验证明："
                "样本数相同但交给 ZSTD 的原始字节差 5.5 倍，若直接喂 float64 应完全相同。"
                "② 磁盘增量法被后台合并干扰（测出缓变 2239B < 恒定 5394B 的反直觉结果），"
                "改用 `vm_zstd_block_*` 计数增量解决。"
                "③ 用 `NOW + t*10` 生成时间戳导致数据落在未来，`count()` 全返回 0，"
                "改用 `NOW - 1200` 起算解决，并总结三种排查方法。"
                "④ `vm_rows` 是累计计数（3722898）而非存量，曾据此算出荒谬的「104 倍」。"
                "**P1×2 已修**：补知识点 2、3 的「类比失效的边界」；"
                "补课 5 遗留伏笔（每块 115.7 行 ≈ 463 字节）的正面回答。"
                "learner 视角：五个实验全部给出**判据**，七条常见误区全部来自本课真实踩坑 |"
            ).format(d=DATE)
            lines.insert(last_row + 1, ROW)
            t = "\n".join(lines)
            log.append("[清单] 已追加课 6 评审记录")
        else:
            log.append("[清单] 课 6 评审记录已存在")
write(p, t)

# ==================================================================
# 3. stages/3-凭什么快凭什么省/README.md
# ==================================================================
print("=" * 60)
print(" 3. 阶段 3 概览 README.md")
print("=" * 60)
p = "stages/3-凭什么快凭什么省/README.md"
t = read(p)
if "课 6" in t and "✅" in t:
    # 检查课 6 是否已标 ✅
    has_l6_done = False
    for ln in t.split("\n"):
        if "课 6" in ln and "✅" in ln:
            has_l6_done = True
            break
    if has_l6_done:
        log.append("[概览] 课 6 已标 ✅")
    else:
        # 尝试把课 6 行改为 ✅
        lines = t.split("\n")
        for i, ln in enumerate(lines):
            if "课 6" in ln and ("⬜" in ln or "待生成" in ln or "[ ]" in ln):
                lines[i] = ln.replace("⬜", "✅").replace("待生成", "已完成").replace("[ ]", "[x]")
                log.append("[概览] 课 6 标 ✅: %s" % ln.strip()[:60])
                break
        t = "\n".join(lines)

# 补核心结论
if "压缩" not in t or "5.583" not in t:
    if "## 核心结论" in t:
        t = t.replace(
            "## 核心结论",
            "## 核心结论\n\n"
            "- **课 6 压缩**：三层流水线 = 列式布局（让规律浮现）+ 值编码（delta-of-delta / Gorilla XOR，把大数变小数）+ ZSTD（实测 5.583 倍，只负责收尾）\n"
            "- 实测每样本字节：恒定 1.02 / 缓变 3.97 / 随机 6.12 —— 真实监控数据约 4 字节\n"
            "- 降采样用老数据精度换保留期，**企业版功能**，适合趋势不适合 SLO\n"
            "- 测量方法论（本课踩坑总结）：验证写入用 `vm_rows_inserted_total`，测压缩用 `vm_zstd_block_*`，算存量用 `count_over_time()`",
            1,
        )
        log.append("[概览] 已补课 6 核心结论")
    else:
        t += (
            "\n\n## 核心结论（课 6 补充）\n\n"
            "- **课 6 压缩**：三层流水线 = 列式布局 + 值编码（delta-of-delta / Gorilla XOR）+ ZSTD（实测 5.583 倍）\n"
            "- 实测每样本字节：恒定 1.02 / 缓变 3.97 / 随机 6.12\n"
            "- 降采样是企业版功能，适合趋势分析，不适合 SLO 计算\n"
            "- 测量方法论：验证写入用 `vm_rows_inserted_total`，测压缩用 `vm_zstd_block_*`，算存量用 `count_over_time()`\n"
        )
        log.append("[概览] 已追加课 6 核心结论")
write(p, t)

# ==================================================================
# 4. 02-课程目录.md 与 01-学习路径总览.md
# ==================================================================
print("=" * 60)
print(" 4. 课程目录 + 学习路径总览")
print("=" * 60)

L6_LINK = "stages/3-凭什么快凭什么省/6-压缩为什么能省7倍空间.md"
p = "02-课程目录.md"
t = read(p)
if L6_LINK in t:
    log.append("[目录] 课 6 链接已存在")
    # 确认有 ✅
    for ln in t.split("\n"):
        if L6_LINK in ln and "✅" not in ln:
            t = t.replace(ln, ln.rstrip() + " ✅")
            log.append("[目录] 课 6 补 ✅ 标记")
            break
else:
    log.append("[WARN] 课程目录缺少课 6 链接，需手动添加")
if "进行中" in t and "课 6" in t:
    pass
write(p, t)

p = "01-学习路径总览.md"
t = read(p)
if "课 5 ✅ 已完成，课 6、课 7 待生成" in t:
    t = t.replace(
        "课 5 ✅ 已完成，课 6、课 7 待生成",
        "课 5、课 6 ✅ 已完成，课 7 待生成",
    )
    log.append("[总览] 阶段 3 进度已更新为「课 5、6 完成」")
if "12 课中已完成 5 课（课 1–5），35 知识点中已完成 17 个" in t:
    t = t.replace(
        "12 课中已完成 5 课（课 1–5），35 知识点中已完成 17 个",
        "12 课中已完成 6 课（课 1–6），35 知识点中已完成 20 个",
    )
    log.append("[总览] 总进度已更新为 6 课 / 20 知识点")
write(p, t)

print()
print("=" * 60)
print(" 回写结果")
print("=" * 60)
for l in log:
    print("  " + l)
