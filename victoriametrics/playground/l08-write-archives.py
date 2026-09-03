# -*- coding: utf-8 -*-
"""
课 8 交付：回写四处档案（用户 2026-09-02 强制要求，缺一不可）
  1. 00-学习档案.md     —— 进度表 + 评审记录
  2. 00-评审清单.md     —— 本课勾选 + 评审记录表追加
  3. stages/4-怎么横向扩展/README.md —— 本课标 ✅ + 核心结论
  4. 02-课程目录.md 与 01-学习路径总览.md —— 索引链接与进度条

前车之鉴：
  - 课 5：评审记录查重用宽松子串，误命中 "- [ ]" 占位项
  - 课 6：脚本只报 WARN 未修复，课程目录链接需手动补
  - 课 7：关键词误勾了课 9（因含「容量」），已回滚；「✅ 未开始」措辞矛盾
  → 本课教训：勾选必须限定在课 8 行，且关键词要精确
"""
import io
import os

ROOT = "/mnt/d/projects/learning/victoriametrics"
DATE = "2026-09-02"
L7_TITLE = "课 7《内存模型与容量规划"
L8_TITLE = "课 8《集群三件套与最小集群实战"
log = []


def read(p):
    with io.open(os.path.join(ROOT, p), encoding="utf-8") as f:
        return f.read()


def write(p, s):
    with io.open(os.path.join(ROOT, p), "w", encoding="utf-8", newline="\n") as f:
        f.write(s)


# ==================================================================
# 1. 00-学习档案.md —— 只勾课 8 行，避免误伤其他课
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
    # 精确限定：这一行必须是课 8 的进度行
    if "课 8" not in ln:
        continue
    lines[i] = ln.replace("⬜", "✅")
    changed += 1
    log.append("[档案] 勾选: %s" % ln.strip()[:60])
t = "\n".join(lines)

# 追加评审记录（紧跟课 7 记录之后）
ROW8 = (
    "| {d} | {t} | 主 agent 内联（pedagogy + learner） | "
    "**P0×0 / P1×0 / P2×2（经核验均为误判，另补 1 处生产提示）**。"
    "核心产出："
    "① **搭起真实集群并跑通全链路**——首次定位到集群版不在 victoria-metrics 仓库"
    "（`-cluster` tag 不存在），而是三个独立仓库 `vminsert`/`vmselect`/`vmstorage`，"
    "tag 为 `v1.151.0-cluster`，与单节点 v1.151.0 严格对齐；"
    "② 证明 **vmstorage 是哑存储**——直接查/写 8482 均返回 **HTTP 400**，"
    "集群智能全在 vminsert/vmselect 两个无状态代理里；"
    "③ 验证**故障隔离**：停掉 vmselect 后写入仍 **HTTP 204**，查询 HTTP 000；"
    "④ 证明**一致性哈希的确定性**：同一条序列 20 个样本全部落到 vmstorage1"
    "（738→739，另一个节点增量 0）；1000 条序列分到两节点 = **509 / 491**；"
    "⑤ 揭示**扩容不迁移旧数据**：229 条旧数据全留在原节点，`-storageNode` 只在启动时读取，"
    "社区版必须重启 vminsert/vmselect；"
    "⑥ **静默降级**实测：停掉一个 vmstorage，count 从 1000 → **509 且不报错**，"
    "恢复后回到 1000——这是课 9 复制因子要解决的首要问题；"
    "⑦ **多租户隔离**验证：tenant 0/42/100 各 5 样本互不干扰，tenant 999 为 0；"
    "并踩出三个坑：projectID 是平级标识（查 `7` 看不到 `7:9`）、"
    "省略租户 ID 缺省为 0、`vm_account_id` 标签需 multitenant 端点才生效；"
    "⑧ 组件内存实测：vmstorage 84.5MB / vminsert 14.8MB / vmselect 33.2MB，"
    "单节点 235.3MB——vminsert 极轻，扩它几乎不花钱。"
    "Agent B 两条 P2 经核验为检测窗口误判（选型清单实有 ✓/⚠ 信号；"
    "docker stop 上下文完整），另主动补了一处生产环境提示 | "
    "通过；无阻塞项 |"
).format(d=DATE, t=L8_TITLE)

if L8_TITLE not in t:
    lines = t.split("\n")
    idx = None
    for i, ln in enumerate(lines):
        if ln.startswith("|") and L7_TITLE in ln:
            idx = i
            break
    if idx is not None:
        end = idx
        while end + 1 < len(lines) and lines[end + 1].startswith((" ", "\t")):
            end += 1
        lines.insert(end + 1, ROW8)
        t = "\n".join(lines)
        log.append("[档案] 已追加课 8 评审记录")
    else:
        log.append("[WARN] 未找到课 7 锚点，评审记录未追加")
else:
    log.append("[档案] 课 8 记录已存在")
write(p, t)
print("  进度表勾选 %d 处（仅课 8 行）" % changed)

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
    if "- [ ]" in ln and "课 8" in ln:
        lines[i] = ln.replace("- [ ]", "- [x]") + " — P0=0（%s）" % DATE
        log.append("[清单] 勾选: %s" % ln.strip()[:60])
        hit = True
        break
if not hit:
    log.append("[WARN] 清单无课 8 占位项")
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
            lines[i].startswith("|") and "课 8《" in lines[i]
            for i in range(rec_idx, last_row + 1)
        )
        if not exists:
            ROW = (
                "| {d} | {t} | 主 agent 内联（pedagogy + learner） | 0 | "
                "**全程真跑实测，8 组实验全部给出判据**。"
                "① 镜像来源纠错：集群版在三个独立仓库，非 `victoria-metrics:-cluster`。"
                "② vmstorage 不能读写（实测 HTTP 400）——shared-nothing 的直接证据。"
                "③ 故障隔离：停 vmselect 后写入仍 204。"
                "④ 哈希确定性：20 样本全落一处；1000 条分 509/491。"
                "⑤ 扩容不迁移：229 条旧数据不动，需重启代理。"
                "⑥ 静默降级：停一节点 count 1000→509 不报错（课 9 伏笔）。"
                "⑦ 多租户三坑：projectID 平级、缺省为 0、vm_account_id 需 multitenant 端点。"
                "⑧ 组件内存：vminsert 仅 14.8MB。"
                "**Agent B 两条 P2 经核验为误判**：L9 选型清单实有 ✓/⚠ 信号"
                "（检测窗口 1500 字符未覆盖）；L8 `docker stop` 位于实验 4，"
                "前后有目标与判据说明。另主动补了一处生产环境提示。"
                "learner 视角：7 条常见误区全部来自真实踩坑，"
                "含课 6 的 `count()` 时序坑在集群环境复现（[10m] 只覆盖 67/100） |"
            ).format(d=DATE, t=L8_TITLE)
            lines.insert(last_row + 1, ROW)
            t = "\n".join(lines)
            log.append("[清单] 已追加课 8 评审记录")
write(p, t)

# ==================================================================
# 3. 阶段 4 概览（课 8 已完成，核心结论已在文件中）
# ==================================================================
print("=" * 60)
print(" 3. 阶段 4 概览 README.md")
print("=" * 60)
p = "stages/4-怎么横向扩展/README.md"
t = read(p)
if "课 8：集群三件套与最小集群实战 ✅ 已完成" in t:
    log.append("[概览] 课 8 已标 ✅（创建时已写入）")
else:
    lines = t.split("\n")
    for i, ln in enumerate(lines):
        if "课 8" in ln and ("⬜" in ln or "待生成" in ln):
            lines[i] = ln.replace("⬜", "✅").replace("待生成", "已完成")
            log.append("[概览] 课 8 标 ✅")
            break
    t = "\n".join(lines)
write(p, t)

# ==================================================================
# 4. 课程目录 + 学习路径总览
# ==================================================================
print("=" * 60)
print(" 4. 课程目录 + 学习路径总览")
print("=" * 60)

L8_LINK = "stages/4-怎么横向扩展/8-集群三件套与最小集群实战.md"
p = "02-课程目录.md"
t = read(p)
if L8_LINK in t:
    log.append("[目录] 课 8 链接已存在")
else:
    lines = t.split("\n")
    for i, ln in enumerate(lines):
        if ln.strip() == "- 课 8：集群三件套与最小集群实战":
            # 替换为带链接 + 子知识点
            lines[i] = (
                "- 课 8：[集群三件套与最小集群实战](%s) ✅\n"
                "  - 知识点 1：为什么拆成三个组件\n"
                "  - 知识点 2：vminsert 与一致性哈希分片\n"
                "  - 知识点 3：vmselect 查询聚合\n"
                "  - 知识点 4：动手搭一个最小集群\n"
                "  - 知识点 5：多租户隔离（实测补充）" % L8_LINK
            )
            log.append("[目录] 已插入课 8 链接 + 知识点")
            break
    t = "\n".join(lines)
write(p, t)

p = "01-学习路径总览.md"
t = read(p)
before = t
if "12 课中已完成 7 课（课 1–7），35 知识点中已完成 23 个" in t:
    t = t.replace("12 课中已完成 7 课（课 1–7），35 知识点中已完成 23 个",
                  "12 课中已完成 8 课（课 1–8），35 知识点中已完成 28 个")
    log.append("[总览] 总进度更新为 8 课 / 28 知识点")
if "阶段 4" in t and "进行中" not in t:
    pass
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
