# -*- coding: utf-8 -*-
"""
课 6 双 agent 评审 · Agent B：learner（学员视角）
检查：零上下文读者能否看懂、能否照着做、会不会被坑
核心判据：假设读者只拿到这份文档，没有代码上下文，他能看懂并照做吗
"""
import io
import re

F = "/mnt/d/projects/learning/victoriametrics/stages/3-凭什么快凭什么省/6-压缩为什么能省7倍空间.md"
with io.open(F, encoding="utf-8") as f:
    t = f.read()

issues = []
print("=" * 60)
print(" Agent B · learner 视角评审")
print("=" * 60)

# L1 环境前置：读者知道在哪执行命令吗
print("\n[L1] 环境前置 · 读者能否知道「在哪跑」")
if "playground" in t and "cd /mnt/d/projects" in t:
    print("   [OK]   给出了工作目录（/mnt/d/projects/.../playground）")
else:
    issues.append(("P1", "未明确说明命令的工作目录"))
if "localhost:8428" in t:
    print("   [OK]   给出了 VM 访问地址（localhost:8428）")
else:
    issues.append(("P1", "未说明 VM 访问地址"))
# 端口/容器名
print("   VM 端口提及: %d 次" % t.count("8428"))

# L2 每个实验是否给了「判据」——读者怎么知道自己做对了
print("\n[L2] 可验证性 · 每个实验是否给出判据")
exp_sec = t.split("## 第四幕")[1].split("## 第五幕")[0] if "## 第四幕" in t else ""
n_exp = exp_sec.count("### 实验")
n_judge = exp_sec.count("**判据**")
print("   实验数: %d   判据数: %d" % (n_exp, n_judge))
if n_judge < n_exp:
    issues.append(("P1", "有 %d 个实验但只有 %d 个判据" % (n_exp, n_judge)))

# L3 踩坑预警：是否把本课真实踩过的坑写进去
print("\n[L3] 踩坑预警 · 本课真实踩过的坑是否记录")
pitfalls = t.split("## 🐞 常见误区")[1].split("## 🚀")[0] if "## 🐞 常见误区" in t else ""
n_pit = pitfalls.count("### ")
print("   误区条数: %d" % n_pit)
must_have = {
    "磁盘增量": "后台合并干扰磁盘增量法",
    "未来": "写入未来时间戳查不到",
    "value": "Influx 字段名拼进指标名",
    "vm_rows": "vm_rows 是累计计数",
    "magic": "不是所有 part 都压缩",
}
for kw, desc in must_have.items():
    hit = kw in pitfalls
    print("   %s %s" % ("[OK]  " if hit else "[MISS]", desc))
    if not hit:
        issues.append(("P1", "未记录踩坑：%s" % desc))

# L4 数字可复现：讲义数字是否标注了「会漂移」
print("\n[L4] 数字可复现性")
drift_markers = ["快照", "会随", "漂移", "小幅", "累计", "实测"]
n_drift = sum(t.count(m) for m in drift_markers)
print("   漂移提示词: %d 处" % n_drift)
if t.count("本机实测") >= 5:
    print("   [OK]   关键数字标注「本机实测」: %d 处" % t.count("本机实测"))
else:
    issues.append(("P2", "关键数字缺少「本机实测」标注"))

# L5 概念首次出现是否有解释
print("\n[L5] 术语解释 · 关键术语首次出现处")
terms = {
    "delta-of-delta": "二阶差分",
    "Gorilla": "Facebook",
    "ZSTD": "magic",
    "降采样": "更粗",
    "magic number": "28 b5 2f fd",
}
for term, clue in terms.items():
    hit = term in t
    explained = clue in t
    status = "[OK]  " if (hit and explained) else "[WARN]"
    print("   %s %-18s 出现=%s 有解释=%s" % (status, term, hit, explained))
    if hit and not explained:
        issues.append(("P2", "术语 %s 出现但缺少解释" % term))

# L6 读者能照着做吗：bash 块是否自包含
print("\n[L6] 命令自包含性")
blocks = re.findall(r"```bash\n(.*?)```", t, re.S)
print("   bash 块: %d 个" % len(blocks))
vague = [b for b in blocks if "xxx" in b or "TODO" in b or "<" in b and "playground" not in b]
if vague:
    print("   [WARN] %d 个块含占位符，读者需自行替换" % len(vague))
    for b in vague[:3]:
        print("      例: %s" % b.strip().split("\n")[0][:60])
else:
    print("   [OK]   无模糊占位符")

# L7 伏笔闭环：课 5 留下的问题课 6 回答了吗
print("\n[L7] 跨课伏笔闭环")
if "115.7" in t:
    print("   [OK]   回应了课 5 的「每块 115.7 行」伏笔")
else:
    issues.append(("P1", "未回应课 5 留下的 115.7 行伏笔"))
if "items.bin" in t and "values.bin" in t:
    print("   [OK]   回应了课 5 的「索引比数据大」伏笔")
else:
    issues.append(("P2", "未回应索引比数据大的伏笔"))

# L8 认知递进：是否先给直觉再给原理
print("\n[L8] 认知递进")
order = []
for marker in ["#### 直觉建立", "#### 核心原理", "#### 示例演示"]:
    order.append((marker, t.find(marker)))
if all(p >= 0 for _, p in order):
    print("   [OK]   三个要素均存在，首次出现顺序正确")
else:
    issues.append(("P0", "六要素顺序缺失"))

print("\n" + "=" * 60)
print(" Agent B 评审结论")
print("=" * 60)
if not issues:
    print("✅ 未发现 P0/P1 问题")
else:
    for lvl, msg in issues:
        print("[%s] %s" % (lvl, msg))
