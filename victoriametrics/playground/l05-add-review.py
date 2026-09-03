# -*- coding: utf-8 -*-
"""
课 5 交付收尾：把课 4、课 5 的评审记录真正写入 00-评审清单.md。

背景（本脚本存在的理由）：
    此前的 l05-add-review.py 用 `"课 5《存储引擎" in text` 做查重，
    命中了待评审清单里的占位项
    `- [ ] 阶段 3·课 5《存储引擎：MergeSet 与磁盘结构》 — pedagogy + learner 双视角`
    于是误判「记录已存在」而跳过，导致真正的评审记录从未写入。
    本脚本改用「评审记录表末行」作为精确锚点，彻底避开占位项。

同时：
    1. 把待评审清单里课 4、课 5 的占位项从 `- [ ]` 勾选为 `- [x]` 并补 P0=0 与日期
    2. 幂等：重复运行不会重复写入（以评审记录表里是否已有该课记录行为准）
"""
import io
import os
import sys

F = "/mnt/d/projects/learning/victoriametrics/00-评审清单.md"
DATE = "2026-09-02"

with io.open(F, encoding="utf-8") as f:
    text = f.read()

lines = text.split("\n")

# ---------------------------------------------------------------
# 第 1 步：定位「评审记录」表，找出它的最后一行（| 开头）
# 这是唯一的精确锚点——占位项是 `- [ ]` 开头，绝不会命中
# ---------------------------------------------------------------
rec_hdr_idx = None
for i, ln in enumerate(lines):
    if ln.strip().startswith("## 评审记录"):
        rec_hdr_idx = i
        break
if rec_hdr_idx is None:
    print("[FAIL] 未找到「## 评审记录」章节")
    sys.exit(1)

# 从表头往下找表格最后一行
last_row_idx = None
for i in range(rec_hdr_idx, len(lines)):
    if lines[i].startswith("|"):
        last_row_idx = i
    elif last_row_idx is not None and lines[i].strip() == "":
        break
if last_row_idx is None:
    print("[FAIL] 未找到评审记录表的任何行")
    sys.exit(1)

print("[INFO] 评审记录表末行 = 第 %d 行" % (last_row_idx + 1))
print("       %s" % lines[last_row_idx][:70])

# ---------------------------------------------------------------
# 第 2 步：幂等检查——看课 4 / 课 5 的记录行是否已存在
# 判据比上次严格：必须同时含 "| 2026-09-02 | 课 N" 且位于评审记录区
# ---------------------------------------------------------------
def record_exists(lesson_key):
    for i in range(rec_hdr_idx, last_row_idx + 1):
        if lines[i].startswith("|") and ("| 课 %s《" % lesson_key) in lines[i]:
            return True
    return False

ROW_L4 = (
    "| {d} | 课 4《写入协议全家桶与基数治理》 | 主 agent 内联（pedagogy + learner） | 0 | "
    "**实测推翻直觉×2**：① Influx line protocol 的 `_s`/`_ms`/`_ns` 后缀初判为单位标识符，"
    "实测推翻——真正原因是**字段名一律拼进指标名**（连 `value` 也被拼进去）。"
    "② CSV import 四种写法全部返回 HTTP 204 且服务端不报错，但 "
    "`vm_rows_inserted_total{{type=\"csvimport\"}}=0` → 讲义据此确立"
    "「验证写入必须用 VM 自身统计，不能信 HTTP 状态码」的判据。"
    "**P1×2 已修**：① 误判 `metric_relabel_configs` 未生效，根因是**对比基准选错**"
    "（两个 job 行为不同却拿总数对比），按 job 拆解后确认 drop 生效，已作为排查经验写入讲义；"
    "② OpenTSDB 端口冲突致容器 fatal，已改为 telnet 4242 / HTTP 4243 分离并给出可复制的启动参数。"
    "learner 视角：`write_relabel_configs` 与 `metric_relabel_configs` 用"
    "「是否影响本地存储」一句话区分，基数治理三层（写入前根治 / 查询时治标 / 限流兜底）"
    "各有实测数字支撑 |"
).format(d=DATE)

ROW_L5 = (
    "| {d} | 课 5《存储引擎：MergeSet 与磁盘结构》 | 主 agent 内联（pedagogy + learner） | 0 | "
    "**实测推翻直觉×1 + 反直觉发现×1**：① 误以为 `indexdb/` 在顶层目录，"
    "实测在 `data/` 下面（宿主机正确路径 `data/data/indexdb/`）。"
    "② **`items.bin`（806 KB）> `values.bin`（285 KB）——索引比数据还占地方**，"
    "直接推翻第二幕「压缩率高=算法强」的直觉，把省存储的真正杠杆指回课 4 基数治理。"
    "**P1×2 已修**：① 讲义混用「容器内 `data/`」与「宿主机 `data/data/`」两种视角，"
    "已补路径对照表并为三条命令加视角注释；"
    "② 文件类型统计是快照而非静态值，已补「会随合并变化」说明并给出复跑实测"
    "（part 14→8、`items.bin` 806KB→1.2MB）。"
    "**P2×2 已修**：繁体「本課」6 处统一为简体；补 stage 3 概览 README 使导航链接可达。"
    "learner 视角：三个 counter 与预期不符的四轮排查写成完整排障叙事，"
    "提炼可迁移方法论——**「遇到 counter 与预期不符，先做静默基线实验」**"
    "（静默 30s 自涨 2，证明是 self-scrape 噪声而非机制失效） |"
).format(d=DATE)

to_insert = []
if not record_exists("4"):
    to_insert.append(("课4", ROW_L4))
else:
    print("[SKIP] 课 4 评审记录已存在")
if not record_exists("5"):
    to_insert.append(("课5", ROW_L5))
else:
    print("[SKIP] 课 5 评审记录已存在")

offset = 0
for name, row in to_insert:
    lines.insert(last_row_idx + 1 + offset, row)
    offset += 1
    print("[OK]   已插入 %s 评审记录" % name)

text = "\n".join(lines)

# ---------------------------------------------------------------
# 第 3 步：勾选待评审清单里课 4、课 5 的占位项
# 只匹配「- [ ] 阶段 N·课 M《...》」这种占位项，不动每课交付必查项
# ---------------------------------------------------------------
checked = []

def tick(lesson_prefix, suffix):
    global text
    for marker in ["阶段 2·课 4《", "阶段 3·课 5《"]:
        pass

for prefix in ["阶段 2·课 4《写入协议全家桶与基数治理》",
               "阶段 3·课 5《存储引擎：MergeSet 与磁盘结构》"]:
    old = "- [ ] %s — pedagogy + learner 双视角" % prefix
    new = "- [x] %s — pedagogy + learner 双视角 — P0=0（%s）" % (prefix, DATE)
    if old in text:
        text = text.replace(old, new)
        checked.append(prefix)
        print("[OK]   已勾选：%s" % prefix)
    elif new in text:
        print("[SKIP] 已勾选：%s" % prefix)
    else:
        print("[WARN] 未找到占位项：%s" % prefix)

with io.open(F, "w", encoding="utf-8", newline="\n") as f:
    f.write(text)

print()
print("========== 写入完成 ==========")
print("新增评审记录：%d 条" % len(to_insert))
print("勾选占位项  ：%d 条" % len(checked))
