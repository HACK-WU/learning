# -*- coding: utf-8 -*-
"""
课 7 双 agent 评审 · Agent A：pedagogy（教学法视角）
改进：知识点篇幅改用「正文边界」截断，不再把后续章节算进最后一个知识点
"""
import io
import re

F = "/mnt/d/projects/learning/victoriametrics/stages/3-凭什么快凭什么省/7-内存模型与容量规划.md"
with io.open(F, encoding="utf-8") as f:
    t = f.read()

lines = t.split("\n")
issues = []

print("=" * 60)
print(" Agent A · pedagogy 视角评审")
print("=" * 60)

# P1 认知负荷：知识点篇幅（用第四幕作为正文结束边界）
print("\n[P1] 认知负荷 · 三个知识点的篇幅分布")
END_MARK = "## 第四幕"
idx_end = next((i for i, ln in enumerate(lines) if ln.startswith(END_MARK)), len(lines))
secs = [(i, ln) for i, ln in enumerate(lines) if ln.startswith("### 知识点")]
for k in range(len(secs)):
    start = secs[k][0]
    end = secs[k + 1][0] if k + 1 < len(secs) else idx_end
    n = end - start
    flag = ""
    if n > 220:
        issues.append(("P1", "%s 篇幅 %d 行偏重" % (secs[k][1][:30], n))); flag = "  ⚠偏重"
    if n < 60:
        issues.append(("P1", "%s 篇幅 %d 行偏轻" % (secs[k][1][:30], n))); flag = "  ⚠偏轻"
    print("   %-40s %5d 行%s" % (secs[k][1][:38], n, flag))

# P2 类比质量
print("\n[P2] 类比质量")
print("   类比引入语: %d 处" % len(re.findall(r"想象你", t)))
print("   类比失效边界: %d 处" % t.count("类比失效的边界"))
if t.count("类比失效的边界") < 3:
    issues.append(("P0", "类比失效边界不足 3 处"))

# P3 冲突感
print("\n[P3] 认知冲突强度")
markers = ["不可能的数字", "冲突点", "反直觉", "陷阱", "这修正了", "推翻"]
n = sum(t.count(m) for m in markers)
print("   冲突标记词: %d 处" % n)
if n < 4:
    issues.append(("P1", "认知冲突强度不足"))

# P4 练习设计
print("\n[P4] 练习设计")
quiz = t.split("## 课后小测")[1].split("## 🚀")[0] if "## 课后小测" in t else ""
nq, na = quiz.count("<summary>"), quiz.count("**答案**")
print("   题目数 %d / 答案数 %d" % (nq, na))
if nq != na or nq < 3:
    issues.append(("P1", "课后小测数量或答案不匹配"))

# P5 五幕节奏
print("\n[P5] 节奏控制")
acts = ["## 第一幕", "## 第二幕", "## 第三幕", "## 第四幕", "## 第五幕"]
pos = []
for a in acts:
    i = next((i for i, ln in enumerate(lines) if ln.startswith(a)), None)
    if i is not None:
        pos.append((a, i))
for k in range(len(pos)):
    start = pos[k][1]
    end = pos[k + 1][1] if k + 1 < len(pos) else len(lines)
    r = (end - start) * 100.0 / len(lines)
    print("   %-10s %5d 行 (%.1f%%)" % (pos[k][0], end - start, r))

# P6 实验可验证性
print("\n[P6] 实验判据")
exp = t.split("## 第四幕")[1].split("## 第五幕")[0] if "## 第四幕" in t else ""
ne, nj = exp.count("### 实验"), exp.count("**判据**")
print("   实验数 %d / 判据数 %d" % (ne, nj))
if nj < ne:
    issues.append(("P1", "%d 个实验中 %d 个缺判据" % (ne, ne - nj)))

# P7 伏笔闭环（课 6 遗留 + 本课自留）
print("\n[P7] 伏笔闭环")
for kw, desc in [("115.7", "回应课 6 数据形态"), ("cache", "修正课 5 的 cache 印象"),
                 ("97.5", "跳过比例"), ("65.5", "边际成本")]:
    print("   %s %s" % ("[OK]  " if kw in t else "[MISS]", desc))

# P8 收官课特性：阶段总结
print("\n[P8] 阶段收官要素")
for kw in ["阶段 3 总答案", "凭什么快", "凭什么省", "共同前提"]:
    hit = kw in t
    print("   %s %s" % ("[OK]  " if hit else "[WARN]", kw))
    if not hit:
        issues.append(("P2", "收官课缺少阶段总结要素：%s" % kw))

print("\n" + "=" * 60)
print(" Agent A 评审结论")
print("=" * 60)
if not issues:
    print("✅ 未发现 P0/P1 问题")
else:
    for lvl, msg in issues:
        print("[%s] %s" % (lvl, msg))
