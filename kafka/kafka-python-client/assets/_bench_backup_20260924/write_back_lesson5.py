"""课 5：回写四处档案。"""
import io

BASE = "/mnt/d/projects/learning/kafka/kafka-python-client"

# ============ 1. 00-学习档案.md ============
P = f"{BASE}/00-学习档案.md"
rows = [
    "| 2 | 课 5 | 消费者内部：Fetcher 与 poll 循环 | ✅ 已完成 | 2026-09-21 | - |\n",
    "| 2 | 课 5 | 再均衡协议与分区分配 | ✅ 已完成 | 2026-09-21 | - |\n",
    "| 2 | 课 5 | 位移提交路径 | ✅ 已完成 | 2026-09-21 | - |\n",
]
with io.open(P, encoding="utf-8") as f:
    lines = f.readlines()
if any("课 5 |" in l for l in lines):
    print("档案：课 5 已存在，跳过")
else:
    out, done = [], False
    for ln in lines:
        if not done and ln.startswith("| 2 | 课 4 | 缓冲区与背压 | ✅"):
            out.append(ln)
            out.extend(rows)
            done = True
        else:
            out.append(ln)
    with io.open(P, "w", encoding="utf-8") as f:
        f.writelines(out)
    print(f"档案：已插入课 5 三行（{done}）")

# ============ 2. 00-评审清单.md ============
P2 = f"{BASE}/00-评审清单.md"
ROW = (
    "| 2026-09-21 | 课 5 消费者内部机制 | 主 agent 内联（pedagogy + learner 双视角，命令照抄复验） | "
    "**P0 清零**。复验连抓 3 个缺陷（均已修）："
    "① 再均衡判定脚本用 `len(set(flat))==4` 判无重叠，对 `[(0,1),(2,),(2,),(3,)]` 有重复也返回 True —— 修正为 `len(flat)==4 and len(set(flat))==4`；"
    "② 单进程多 consumer 读到 `assignment()` 重复分区，是再均衡中间态而非 Kafka 行为 —— 改为 4 独立进程 + 连续稳定 12s 才判定，最终 `[0][1][2][3]` 零重叠；"
    "③ `kafka-consumer-groups.sh` 一直返回空，根因是课 4 装的 JMX Exporter 占端口致 CLI 启动失败（`BindException: Address in use`）—— 工具坏非 Kafka 坏 | "
    "已修并复验通过：位移双轨二次确认、链接零断链、集群无残留 |\n"
)
with io.open(P2, encoding="utf-8") as f:
    lines2 = f.readlines()
if any("课 5 消费者内部机制" in l for l in lines2):
    print("评审清单：课 5 已存在，跳过")
else:
    out, done = [], False
    for ln in lines2:
        if not done and ln.startswith("| 2026-09-21 | 课 4 生产者内部机制"):
            out.append(ROW)
            done = True
        out.append(ln)
    with io.open(P2, "w", encoding="utf-8") as f:
        f.writelines(out)
    print(f"评审清单：已插入课 5 记录（{done}）")

# ============ 3. 02-课程目录.md ============
P3 = f"{BASE}/02-课程目录.md"
with io.open(P3, encoding="utf-8") as f:
    s3 = f.read()
old3 = "- 课 5：消费者内部机制（待讲解）"
new3 = "- 课 5：[消费者内部机制](./stages/2-理解层-协议与源码/课5-消费者内部机制.md)（✅ 已讲解）"
if old3 in s3:
    s3 = s3.replace(old3, new3)
    with io.open(P3, "w", encoding="utf-8") as f:
        f.write(s3)
    print("课程目录：课 5 已改为链接")
else:
    print("课程目录：课 5 已处理过")

# ============ 4. 阶段 overview.md ============
P4 = f"{BASE}/stages/2-理解层-协议与源码/overview.md"
with io.open(P4, encoding="utf-8") as f:
    s4 = f.read()
old4 = "| 课 5 | 消费者内部机制 | poll 一次到底做了什么、位移怎么提交 | ⬜ 未开始 |"
new4 = "| 课 5 | [消费者内部机制](./课5-消费者内部机制.md) | poll 一次到底做了什么、位移怎么提交 | ✅ 已完成 |"
if old4 in s4:
    s4 = s4.replace(old4, new4)
    with io.open(P4, "w", encoding="utf-8") as f:
        f.write(s4)
    print("阶段 overview：课 5 已标完成")
else:
    print("阶段 overview：课 5 已处理过")

# ============ 5. 01-学习路径总览.md ============
P5 = f"{BASE}/01-学习路径总览.md"
with io.open(P5, encoding="utf-8") as f:
    s5 = f.read()
old5 = "4 阶段 / 13 课，已完成 4 课（课 1–4），当前阶段 2 进行中（课 5 待开始）。"
new5 = "4 阶段 / 13 课，已完成 5 课（课 1–5），当前阶段 2 进行中（课 6 待开始）。"
if old5 in s5:
    s5 = s5.replace(old5, new5)
else:
    new5b = "4 阶段 / 13 课，已完成 5 课（课 1–5）"
    if new5b not in s5:
        s5 = s5.replace("已完成 4 课（课 1–4）", "已完成 5 课（课 1–5）")
        s5 = s5.replace("（课 5 待开始）", "（课 6 待开始）")

add5 = """
## 课 5 实测结论（2026-09-21）

| 结论 | 证据 |
|---|---|
| `poll()` 先管心跳再拉数据 | 源码 `_poll_once` 五步：coordinator.poll → refresh_committed → reset/validate → fetch_records → sleep |
| 消费进度有两份 | 实测消费 10 条：`position=10` 但 `committed=None`；重开后**同一批重放** |
| 自动提交与"处理完"无关 | 按 `auto_commit_interval_ms`（5s）定时提交，实测 `committed=20` |
| 位移记在消费端内存 | `fetcher.py` L582：`self._subscriptions.assignment[tp].position = ...` |
| 4 分区均分 4 消费者 | 独立进程 + 连续稳定 12s 判定：`#1=[0] #2=[1] #3=[2] #4=[3]` 零重叠 |
| 本地 `assignment()` 是中间态 | 收敛轨迹 `#1: (0,1,2,3)→(0,1)→(0)`，`#2: ()→(1)` |
| `max_poll_interval_ms=300000` 是隐形杀手 | 单条处理超 5 分钟 → 被踢 → 分区转出 → 重复消费 |
"""
if "课 5 实测结论" not in s5:
    s5 = s5.rstrip() + "\n" + add5
with io.open(P5, "w", encoding="utf-8") as f:
    f.write(s5)
print("路径总览：已更新进度 + 课 5 结论")
