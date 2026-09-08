"""实战项目评审辅助校验（pedagogy + learner 双视角共用）

只做机械可判定的检查，人工判断部分见评审结论。
用法：python review-check.py
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
BASE = os.path.dirname(ROOT)  # 多集群统一监控平台/

issues = []  # (级别, 视角, 描述)


def read(rel):
    p = os.path.join(BASE, rel)
    if not os.path.exists(p):
        return ""
    with open(p, encoding="utf-8") as f:
        return f.read()


def chk(level, view, desc, cond):
    if not cond:
        issues.append((level, view, desc))


readme = read("README.md")
decision = read("设计决策.md")
anti = read("反例对照.md")
checklist = read("验收清单.md")

# ---------- A1 结构完整性 ----------
for name, content in [("README.md", readme), ("设计决策.md", decision),
                      ("反例对照.md", anti), ("验收清单.md", checklist)]:
    chk("P0", "A1", f"{name} 缺失或为空", len(content) > 500)

# ---------- A2 决策点真权衡（五段式） ----------
n_dec = len(re.findall(r"^## 决策点 \d+", decision, re.M))
chk("P0", "A2", f"决策点数量应 >=2，实际 {n_dec}", n_dec >= 2)

# 每个决策点必须含五段
blocks = re.split(r"^## 决策点 \d+", decision, flags=re.M)[1:]
required = ["候选方案", "最终选择", "选择理由", "代价", "改选"]
for i, b in enumerate(blocks, 1):
    for kw in required:
        chk("P1", "A2", f"决策点 {i} 缺少五段式中的「{kw}」", kw in b)

# 决策点不能是"唯一正确答案"：必须出现对比或让步表述
for i, b in enumerate(blocks, 1):
    has_alt = bool(re.search(r"(为什么不要|放弃|另一种|改选|替代)", b))
    chk("P0", "A2", f"决策点 {i} 未说明放弃的方案（不像真权衡）", has_alt)

# ---------- A3 知识点地图跨阶段 ----------
stages = set(re.findall(r"阶段 (\d+) · 课", readme))
chk("P0", "A3", f"知识点地图覆盖阶段数应 >=3，实际 {len(stages)}", len(stages) >= 3)

# 每个知识点都要有讲义链接
rows = [l for l in readme.splitlines() if re.match(r"^\|.*阶段 \d+ · 课", l)]
bad_link = [r[:40] for r in rows if "](../../stages/" not in r]
chk("P1", "A3", f"有 {len(bad_link)} 行知识点缺讲义回指链接", not bad_link)

# ---------- A4 反例"看起来能跑" ----------
anti_diff = len(re.findall(r"### 差异 \d+", anti))
chk("P0", "A4", f"反例差异条数应 >=3，实际 {anti_diff}", anti_diff >= 3)
# 反例不能是"明显错误"——必须有"看起来没问题"段
chk("P0", "A4", "反例缺「看起来没问题」段（明显错误无教学价值）",
    "看起来没问题" in anti)

# ---------- A5 实现可运行（文件齐全） ----------
impl = os.path.join(BASE, "实现")
must = ["docker-compose.yml", "verify.sh", "app/app.py", "app/Dockerfile",
        "mimir/mimir-config.yml", "rules/alerts.yml",
        "alertmanager/alertmanager.yml", "webhook/webhook_logger.py",
        "prometheus/prometheus-prod.yml", "prometheus/prometheus-global.yml"]
missing = [m for m in must if not os.path.exists(os.path.join(impl, m))]
chk("P0", "A5", f"缺少实现文件: {missing}", not missing)

# ---------- A6 可运行性标注 ----------
chk("P0", "A6", "README 未注明运行方式（docker compose up）",
    "docker compose up" in readme)
chk("P1", "A6", "README 未注明实测环境（版本/平台）",
    re.search(r"WSL|Ubuntu|Docker \d", readme) is not None)
chk("P1", "A6", "README 未标注实测日期",
    re.search(r"20\d\d-\d\d-\d\d", readme) is not None)

# ---------- B 证据纪律 ----------
# 结论必须有实测支撑，不能凭空断言
for kw in ["实测", "实测值", "本机"]:
    chk("P1", "B", f"文档缺少「{kw}」类实测标注",
        any(kw in c for c in [readme, decision, anti, checklist]))

# 数值断言要有出处（避免编造）
chk("P1", "B", "README 缺少实测基线表",
    "实测基线" in readme or "实测结论" in readme)

# ---------- learner 视角：可执行性 ----------
# 命令必须可复制（不能出现"同上"）
for name, content in [("README.md", readme), ("验收清单.md", checklist)]:
    chk("P0", "learner", f"{name} 出现「（同上）」导致照抄无法执行",
        "（同上）" not in content)

# 验收项必须可勾选
chk("P1", "learner", "验收清单缺少可勾选的复选框",
    "- [ ]" in checklist)

# ---------- pedagogy 视角：五幕/六要素 ----------
chk("P2", "pedagogy", "缺少「为什么做这个项目」的动机说明",
    "为什么要做这个项目" in readme)
chk("P2", "pedagogy", "缺少架构图（Mermaid 或 SVG）",
    "```mermaid" in readme or ".svg" in readme)

# ---------- 输出 ----------
level_order = {"P0": 0, "P1": 1, "P2": 2}
issues.sort(key=lambda x: level_order.get(x[0], 9))

print("=" * 50)
print(" 实战项目评审校验")
print("=" * 50)
if not issues:
    print("无问题")
else:
    for lv, view, desc in issues:
        print(f"[{lv}][{view}] {desc}")
print("=" * 50)
counts = {}
for lv, _, _ in issues:
    counts[lv] = counts.get(lv, 0) + 1
print("统计: " + "  ".join(f"{k}={v}" for k, v in sorted(counts.items())))
sys.exit(1 if counts.get("P0", 0) else 0)
