"""课 6：回写四处档案（阶段 2 收尾）。"""
import io

BASE = "/mnt/d/projects/learning/kafka/kafka-python-client"

# ============ 1. 00-学习档案.md ============
P = f"{BASE}/00-学习档案.md"
rows = [
    "| 2 | 课 6 | 确认语义与幂等：三种语义源码级解释 | ✅ 已完成 | 2026-09-21 | - |\n",
    "| 2 | 课 6 | 幂等生产者的实现 | ✅ 已完成 | 2026-09-21 | - |\n",
    "| 2 | 课 6 | at-least-once 为什么会重复 | ✅ 已完成 | 2026-09-21 | - |\n",
]
with io.open(P, encoding="utf-8") as f:
    lines = f.readlines()
if any("课 6 |" in l for l in lines):
    print("档案：课 6 已存在，跳过")
else:
    out, done = [], False
    for ln in lines:
        if not done and ln.startswith("| 2 | 课 5 | 位移提交路径 | ✅"):
            out.append(ln)
            out.extend(rows)
            done = True
        else:
            out.append(ln)
    with io.open(P, "w", encoding="utf-8") as f:
        f.writelines(out)
    print(f"档案：已插入课 6 三行（{done}）")

# ============ 2. 00-评审清单.md ============
P2 = f"{BASE}/00-评审清单.md"
ROW = (
    "| 2026-09-21 | 课 6 确认语义与幂等 | 主 agent 内联（pedagogy + learner 双视角，命令照抄复验） | "
    "**P0 清零**。复验全绿：八组幂等配置行为一致、PID 惰性初始化复现（发送前 -1 → 发送后 4013）、"
    "跨会话 PID 各异（3015/2009/4014）、语义边界铁证（重复 10 条但 topic 恒为 10 条）。"
    "本轮自查修正 1 处：首版 warning 捕获因 logging handler 挂在 root 之后被覆盖而误判为「无 warning」，"
    "改用显式 Handler 后抓到原文 `Idempotence will be disabled because user-provided config conflicts with idempotent defaults: acks=0` | "
    "已修并复验：链接零断链、集群无 l1~l6 残留 |\n"
)
with io.open(P2, encoding="utf-8") as f:
    lines2 = f.readlines()
if any("课 6 确认语义与幂等" in l for l in lines2):
    print("评审清单：课 6 已存在，跳过")
else:
    out, done = [], False
    for ln in lines2:
        if not done and ln.startswith("| 2026-09-21 | 课 5 消费者内部机制"):
            out.append(ROW)
            done = True
        out.append(ln)
    with io.open(P2, "w", encoding="utf-8") as f:
        f.writelines(out)
    print(f"评审清单：已插入课 6 记录（{done}）")

# ============ 3. 02-课程目录.md ============
P3 = f"{BASE}/02-课程目录.md"
with io.open(P3, encoding="utf-8") as f:
    s3 = f.read()
old3 = "- 课 6：确认语义与幂等（待讲解）"
new3 = "- 课 6：[确认语义与幂等](./stages/2-理解层-协议与源码/课6-确认语义与幂等.md)（✅ 已讲解）"
if old3 in s3:
    s3 = s3.replace(old3, new3)
    with io.open(P3, "w", encoding="utf-8") as f:
        f.write(s3)
    print("课程目录：课 6 已改为链接")
else:
    print("课程目录：课 6 已处理过")

# ============ 4. 阶段 overview.md ============
P4 = f"{BASE}/stages/2-理解层-协议与源码/overview.md"
with io.open(P4, encoding="utf-8") as f:
    s4 = f.read()
old4 = "| 课 6 | 确认语义与幂等 | 三种语义源码级差异、幂等实现、at-least-once 重复 | ⬜ 未开始 |"
new4 = "| 课 6 | [确认语义与幂等](./课6-确认语义与幂等.md) | 三种语义源码级差异、幂等实现、at-least-once 重复 | ✅ 已完成 |"
if old4 in s4:
    s4 = s4.replace(old4, new4)
else:
    import re
    s4 = re.sub(r"\| 课 6 \|[^|]*\|([^|]*)\|\s*⬜ 未开始 \|",
                r"| 课 6 | [确认语义与幂等](./课6-确认语义与幂等.md) |\1 | ✅ 已完成 |", s4)
# 阶段状态
s4 = s4.replace("**阶段状态**：进行中", "**阶段状态**：✅ 已完成")
with io.open(P4, "w", encoding="utf-8") as f:
    f.write(s4)
print("阶段 overview：课 6 已标完成，阶段 2 收尾")

# ============ 5. 01-学习路径总览.md ============
P5 = f"{BASE}/01-学习路径总览.md"
with io.open(P5, encoding="utf-8") as f:
    s5 = f.read()
s5 = s5.replace("已完成 5 课（课 1–5）", "已完成 6 课（课 1–6）")
s5 = s5.replace("（课 6 待开始）", "（课 7 待开始）")
s5 = s5.replace("当前阶段 2 进行中", "阶段 2 已完成，当前阶段 3")

add6 = """
## 课 6 实测结论（2026-09-21 · 阶段 2 收尾）

| 结论 | 证据 |
|---|---|
| 3.0.11 默认开幂等（KIP-679） | `enable_idempotence=True`、`acks=-1`、`retries=inf`、`inflight=5` |
| 隐式冲突会**静默关闭**幂等 | 实测 `acks=0` / `retries=0` / `inflight=10` 三档均变 `False`，仅一行 warning |
| 显式 `True` 则抛异常 | `KafkaConfigurationError: enable_idempotence=True is incompatible with user-provided acks=0` |
| PID 惰性初始化 | 发送前 `(-1,-1)` → 发送后 `(4013, 0)`；`_sequence_numbers` 从 0 起 |
| 幂等**跨会话失效** | 三个实例 PID 各异：`3015 / 2009 / 4014` |
| **幂等管写不管读** | 重复消费 10 条，但 topic 恒为 10 条 → 重复在消费侧 |
| `isolation_level` 默认 `read_uncommitted` | 会读到未提交/已中止事务消息（课 8 展开） |
"""
if "课 6 实测结论" not in s5:
    s5 = s5.rstrip() + "\n" + add6
with io.open(P5, "w", encoding="utf-8") as f:
    f.write(s5)
print("路径总览：已更新进度 + 课 6 结论")
