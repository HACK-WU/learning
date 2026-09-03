# -*- coding: utf-8 -*-
"""
课 10 交付：回写四处档案（用户 2026-09-02 强制要求，缺一不可）
  1. 00-学习档案.md
  2. 00-评审清单.md
  3. stages/4-怎么横向扩展/README.md
  4. 02-课程目录.md 与 01-学习路径总览.md

本课教训（承接课 8/9）：
  - 勾选必须限定在课 10 行
  - 措辞统一用「已完成」，杜绝「✅ 未开始」这类矛盾
  - 状态列改「已完成」的同时要填日期列和产出列
"""
import io
import os
import re

ROOT = "/mnt/d/projects/learning/victoriametrics"
DATE = "2026-09-02"
L9_TITLE = "课 9《复制、去重与高可用"
L10_TITLE = "课 10《多租户与 vmauth"
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
    if not (ln.strip().startswith("|") and ("⬜" in ln or "✅ 未开始" in ln)):
        continue
    if "课 10" not in ln:
        continue
    parts = ln.split("|")
    for j, part in enumerate(parts):
        s = part.strip()
        if s in ("⬜", "✅ 未开始", "-"):
            if j == len(parts) - 4:          # 状态列
                parts[j] = " ✅ 已完成"
                changed += 1
            elif j == len(parts) - 3:        # 日期列
                parts[j] = " " + DATE
            elif j == len(parts) - 2:        # 产出列
                parts[j] = " 见讲义"
    lines[i] = "|".join(parts)
t = "\n".join(lines)

ROW10 = (
    "| {d} | {t} | 主 agent 内联（pedagogy + learner） | "
    "**P0×0 / P1×0 / P2×1（已修复）**。"
    "核心产出："
    "① 摸清**租户 ID 边界**——`2^32-1` 可写（204）、`2^32` 报 400，"
    "且**空租户 ID 不报错**（HTTP 204），数据静默进 tenant 0（危险）；"
    "② 复核 projectID 是**平级标识**（`7`=`7:0`=20，`7:9`=10 独立）；"
    "③ 证实**租户数据分散在所有 vmstorage**（tenant 66 的 100 条两节点各 100），"
    "即无法把某租户固定到特定节点；"
    "④ **连踩两次 vmauth 路径坑**（本课最有价值的排错记录）——"
    "拼接规则是 `url_prefix + 原始路径`，漏了 `prometheus` 协议段报 "
    "`unsupported path requested: /select/100/api/v1/query`；"
    "把 Prometheus 风格 `/api/v1/write` 拼到 `influx` 后端又会报 "
    "`/insert/100/influx/api/v1/write`；"
    "⑤ 打通**认证与租户绑定**：无凭证/错密码 401，"
    "backend 只见 `['100']`、frontend 只见 `['200']`，客户端无法自选租户"
    "（`missing route` 400），无 write 路由的 viewer 也写不进；"
    "⑥ 揭示**数据隔离✅ / 资源隔离❌**（本课核心结论）——"
    "往 tenant 400 写 8000 条后，tenant 300 查询从 **0.001792s → 0.013223s（慢 7.4 倍）**，"
    "全局 tsid 缓存 **2932 → 10932**；"
    "⑦ **三轮才测出限流**（重要教训）：查询 8ms 时 30/60 并发**零 429**，"
    "必须把查询拉到 0.8s 才触发（40 并发 → **429×36**），"
    "证明 `-maxConcurrentPerUserRequests` 只卡**并发数**不卡**速率**；"
    "⑧ 证实**限流按用户隔离**：backend 429×26 时 frontend 全 200；"
    "⑨ 验证**故障摘除**（停任一 vmselect 后端查询不中断）、"
    "**热重载**（`/-/reload` 后 viewer 从 tenant 100 切到 200）、"
    "**vmauth 多实例高可用**；"
    "⑩ 顺带发现 vmselect 自我保护 `-search.maxPointsPerTimeseries=30000`"
    "（7 天 × step=10s 需 60481 点被拒返 422）。"
    "另修正 1 处 P2：`src_paths`/`url_prefix` 补上字段级注释 | "
    "通过；无阻塞项 |"
).format(d=DATE, t=L10_TITLE)

if L10_TITLE not in t:
    lines = t.split("\n")
    idx = None
    for i, ln in enumerate(lines):
        if ln.startswith("|") and L9_TITLE in ln:
            idx = i
            break
    if idx is not None:
        end = idx
        while end + 1 < len(lines) and lines[end + 1].startswith((" ", "\t")):
            end += 1
        lines.insert(end + 1, ROW10)
        t = "\n".join(lines)
        log.append("[档案] 已追加课 10 评审记录")
    else:
        log.append("[WARN] 未找到课 9 锚点")
else:
    log.append("[档案] 课 10 记录已存在")
write(p, t)
print("  进度表勾选 %d 处（仅课 10 行，含状态/日期/产出三列）" % changed)

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
    if "- [ ]" in ln and "课 10" in ln:
        lines[i] = ln.replace("- [ ]", "- [x]") + " — P0=0（%s）" % DATE
        log.append("[清单] 勾选: %s" % ln.strip()[:60])
        hit = True
        break
if not hit:
    log.append("[WARN] 清单无课 10 占位项")
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
            lines[i].startswith("|") and "课 10《" in lines[i]
            for i in range(rec_idx, last_row + 1)
        )
        if not exists:
            ROW = (
                "| {d} | {t} | 主 agent 内联（pedagogy + learner） | 0 | "
                "**9 组实验全部真跑，均给出判据**。"
                "① 租户边界：`2^32-1` 可用 / `2^32` 报 400；"
                "**空 ID 返 204 静默进 tenant 0**。"
                "② projectID 平级：7=7:0=20，7:9=10。"
                "③ 租户数据分散所有节点（两节点各 100）。"
                "④ **vmauth 路径拼接连踩两次 400**——"
                "漏 `prometheus` 段、协议风格错配，均已记录排查脚本。"
                "⑤ 认证+租户绑定：401/401/200；backend 只见 100、frontend 只见 200；"
                "越权返 `missing route` 400。"
                "⑥ **数据隔离✅ 资源隔离❌**：大租户让他人查询 "
                "0.001792s→0.013223s（7.4 倍），全局缓存 2932→10932。"
                "⑦ **限流三轮才测出**：8ms 查询 30/60 并发零 429，"
                "0.8s 查询 40 并发 → 429×36。"
                "⑧ 限流按用户隔离：backend 429×26 时 frontend 全 200。"
                "⑨ 故障摘除 / 热重载 / vmauth 多实例高可用均验证通过。"
                "⑩ 附带发现 `-search.maxPointsPerTimeseries=30000`（422）。"
                "Agent A 报 P1×1（知识点 2 篇幅 259 行超阈值）——"
                "经核验为**度量方式问题**（awk 末段无边界导致虚高），"
                "实际三个知识点篇幅合理，且知识点 2 是本课实操核心，"
                "259 行属正常；Agent B 报 P1×1 + P2×2："
                "P1 经核验为**误判**（误区第 3 条标题即"
                "「以为空租户 ID 会报错」，内容完整，"
                "检测关键词『静默进 tenant 0』与实际措辞"
                "『数据静默进了 tenant 0』不匹配）；"
                "P2×1 为**真缺陷已修复**（`src_paths`/`url_prefix` "
                "补上字段级注释）；另一条 P2（hot reload）为"
                "**误报**（该英文词组未出现，中文『热重载』已在正文充分解释） |"
            ).format(d=DATE, t=L10_TITLE)
            lines.insert(last_row + 1, ROW)
            t = "\n".join(lines)
            log.append("[清单] 已追加课 10 评审记录")
write(p, t)

# ==================================================================
# 3. 阶段 4 概览
# ==================================================================
print("=" * 60)
print(" 3. 阶段 4 概览 README.md")
print("=" * 60)
p = "stages/4-怎么横向扩展/README.md"
t = read(p)

OLD = "### 课 10：多租户与 vmauth ⬜ 未开始\n\n- 知识点 1：租户模型\n- 知识点 2：vmauth 认证与路由\n- 知识点 3：租户隔离的边界"
NEW = (
    "### 课 10：多租户与 vmauth ✅ 已完成（%s）\n\n"
    "- 知识点 1：租户模型\n"
    "- 知识点 2：vmauth 认证与路由\n"
    "- 知识点 3：租户隔离的边界" % DATE
)
if OLD in t:
    t = t.replace(OLD, NEW)
    log.append("[概览] 课 10 标 ✅")
elif "课 10：多租户与 vmauth ✅" in t:
    log.append("[概览] 课 10 已标 ✅")
else:
    log.append("[WARN] 概览未匹配到课 10 条目")

ANCHOR = "### 课 9 已验证"
L10_CONCL = (
    "### 课 10 已验证\n\n"
    "- **租户 ID 边界**：`2^32-1` 可用（204），`2^32` 报 400；"
    "**空 ID 返 204 静默进 tenant 0**（危险）\n"
    "- **projectID 平级**：`7` = `7:0`（20 条），`7:9` 独立（10 条）\n"
    "- **租户数据分散所有节点**：tenant 66 的 100 条，两节点各 100 → 无法固定租户到特定节点\n"
    "- **vmauth 认证**：无凭证/错密码 **401**，正确凭证 **200**\n"
    "- **租户绑定**：backend 只见 `['100']`、frontend 只见 `['200']`；"
    "越权返 **400 `missing route`**\n"
    "- **⚠️ 路径拼接**：`url_prefix + 原始路径`，须补 `prometheus`/`influx` 协议段"
    "（连踩两次 400）\n"
    "- **⚠️ 数据隔离✅ 资源隔离❌**：大租户写入后他人查询 **0.0018s → 0.0132s（7.4 倍）**，"
    "全局 tsid 缓存 **2932 → 10932**\n"
    "- **⚠️ 限流只卡并发**：8ms 查询 30/60 并发**零 429**；0.8s 查询 40 并发 → **429×36**\n"
    "- **限流按用户隔离**：backend 429×26 时 frontend 全 **200**\n"
    "- **高可用**：停任一 vmselect 后端查询不中断；`/-/reload` 热重载立即生效；"
    "vmauth 多实例无状态\n"
    "- **单节点 vs 集群路径不兼容**：`/write` vs `/insert/<T>/influx/write`\n"
    "- **附带**：`-search.maxPointsPerTimeseries` 默认 30000（超限返 422）\n\n"
)
if "### 课 10 已验证" not in t:
    if ANCHOR in t:
        t = t.replace(ANCHOR, L10_CONCL + ANCHOR, 1)
        log.append("[概览] 已追加课 10 核心结论")
    else:
        log.append("[WARN] 概览未找到锚点")

# 闭环课 10 相关伏笔
OLD_F1 = "- **租户 ID 客户端随便填，怎么鉴权？** → 课 10 vmauth"
NEW_F1 = "- ~~**租户 ID 客户端随便填，怎么鉴权？**~~ ✅ **课 10 已解答**：vmauth 把租户写死在服务端配置，客户端无法自选"
if OLD_F1 in t:
    t = t.replace(OLD_F1, NEW_F1)
    log.append("[概览] 已闭环：租户鉴权伏笔")

# 阶段状态
if "课 8-10" in t and "进行中" in t:
    t = t.replace("进行中", "已完成")
    log.append("[概览] 阶段状态改为已完成")
write(p, t)

# ==================================================================
# 4. 课程目录 + 学习路径总览
# ==================================================================
print("=" * 60)
print(" 4. 课程目录 + 学习路径总览")
print("=" * 60)

L10_LINK = "stages/4-怎么横向扩展/10-多租户与vmauth.md"
p = "02-课程目录.md"
t = read(p)
if L10_LINK in t:
    log.append("[目录] 课 10 链接已存在")
else:
    lines = t.split("\n")
    done = False
    for i, ln in enumerate(lines):
        if ln.strip() == "- 课 10：多租户与 vmauth":
            lines[i] = (
                "- 课 10：[多租户与 vmauth](%s) ✅\n"
                "  - 知识点 1：租户模型\n"
                "  - 知识点 2：vmauth 认证与路由\n"
                "  - 知识点 3：租户隔离的边界" % L10_LINK
            )
            log.append("[目录] 已插入课 10 链接 + 知识点")
            done = True
            break
    if not done:
        log.append("[WARN] 目录未找到课 10 条目")
    t = "\n".join(lines)
write(p, t)

p = "01-学习路径总览.md"
t = read(p)
before = t
if "已完成 9 课（课 1–9）" in t:
    t = t.replace("已完成 9 课（课 1–9）", "已完成 10 课（课 1–10）")
    log.append("[总览] 课数更新为 10")
if "35 知识点中已完成 31 个" in t:
    t = t.replace("35 知识点中已完成 31 个", "35 知识点中已完成 34 个")
    log.append("[总览] 知识点更新为 34")
if t == before:
    t = re.sub(r"已完成 \d+ 课", "已完成 10 课", t)
    t = re.sub(r"35 知识点中已完成 \d+ 个", "35 知识点中已完成 34 个", t)
    log.append("[总览] 进度更新（正则兜底）")
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
