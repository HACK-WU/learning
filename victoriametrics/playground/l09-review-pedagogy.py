# -*- coding: utf-8 -*-
"""
课 9 双 agent 评审 · Agent A：pedagogy（教学法视角）
"""
import io
import re

F = "/mnt/d/projects/learning/victoriametrics/stages/4-怎么横向扩展/9-复制去重与高可用.md"
with io.open(F, encoding="utf-8") as f:
    t = f.read()

lines = t.split("\n")
issues = []

print("=" * 60)
print(" Agent A · pedagogy 视角评审")
print("=" * 60)

print("\n[P1] 认知负荷 · 三个知识点的篇幅分布")
END_MARK = "## 第四幕"
idx_end = next((i for i, ln in enumerate(lines) if ln.startswith(END_MARK)), len(lines))
secs = [(i, ln) for i, ln in enumerate(lines) if ln.startswith("### 知识点")]
for k in range(len(secs)):
    start = secs[k][0]
    end = secs[k + 1][0] if k + 1 < len(secs) else idx_end
    n = end - start
    flag = ""
    if n > 240:
        issues.append(("P1", "%s 篇幅 %d 行偏重" % (secs[k][1][:30], n))); flag = "  偏重"
    if n < 60:
        issues.append(("P1", "%s 篇幅 %d 行偏轻" % (secs[k][1][:30], n))); flag = "  偏轻"
    print("   %-40s %5d 行%s" % (secs[k][1][:38], n, flag))

print("\n[P2] 类比质量")
print("   类比引入语: %d 处" % len(re.findall(r"想象", t)))
print("   类比失效边界: %d 处" % t.count("类比失效的边界"))
if t.count("类比失效的边界") < 3:
    issues.append(("P0", "类比失效边界不足 3 处"))

print("\n[P3] 认知冲突强度")
markers = ["不报错", "冲突", "反直觉", "陷阱", "为什么", "等等", "静默"]
n = sum(t.count(m) for m in markers)
print("   冲突标记词: %d 处" % n)
if n < 5:
    issues.append(("P2", "认知冲突强度一般"))

print("\n[P4] 练习设计")
quiz = t.split("## 课后小测")[1].split("## 🚀")[0] if "## 课后小测" in t else ""
nq, na = quiz.count("<summary>"), quiz.count("**答案**")
print("   题目数 %d / 答案数 %d" % (nq, na))
if nq != na or nq < 3:
    issues.append(("P1", "课后小测数量或答案不匹配"))

print("\n[P5] 五幕节奏")
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
if len(pos) >= 3:
    third_len = (pos[3][1] if len(pos) > 3 else len(lines)) - pos[2][1]
    first_two = ((pos[1][1] - pos[0][1]) + (pos[2][1] - pos[1][1]))
    if third_len < first_two:
        issues.append(("P2", "第三幕篇幅应大于前两幕之和"))

print("\n[P6] 实验可验证性")
exp = t.split("## 第四幕")[1].split("## 第五幕")[0] if "## 第四幕" in t else ""
ne, nj = exp.count("### 实验"), exp.count("**判据**")
print("   实验数 %d / 判据数 %d" % (ne, nj))
if nj < ne:
    issues.append(("P1", "%d 个实验中 %d 个缺判据" % (ne, ne - nj)))

print("\n[P7] 跨课伏笔闭环（课 8 遗留）")
for kw, desc in [("509", "回应课 8 的静默降级"), ("1000", "课 8 的分片基线"),
                 ("shared-nothing", "延续课 8 架构"), ("一致性哈希", "延续课 8 分片")]:
    hit = kw in t
    print("   %s %s" % ("[OK]  " if hit else "[MISS]", desc))
    if not hit:
        issues.append(("P2", "未闭环：%s" % desc))

print("\n[P8] 数字可信度标注")
print("   本机实测标注: %d 处" % t.count("本机实测"))
if t.count("本机实测") < 5:
    issues.append(("P2", "关键数字缺少本机实测标注"))

print("\n[P9] 认知递进：每步解决一个问题又引入新问题")
chain = all(k in t for k in ["翻倍", "误删", "不自动补齐"])
print("   三步递进链条完整: %s" % chain)
if not chain:
    issues.append(("P2", "缺少'解决问题→引入新问题'的递进叙事"))

print("\n" + "=" * 60)
print(" Agent A 评审结论")
print("=" * 60)
if not issues:
    print("✅ 未发现 P0/P1 问题")
else:
    for lvl, msg in issues:
        print("[%s] %s" % (lvl, msg))
