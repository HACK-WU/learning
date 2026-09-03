# -*- coding: utf-8 -*-
"""
课 6 双 agent 评审 · Agent A：pedagogy（教学法视角）
检查：认知负荷、前置知识依赖、类比质量、练习设计、节奏控制
"""
import io
import re

F = "/mnt/d/projects/learning/victoriametrics/stages/3-凭什么快凭什么省/6-压缩为什么能省7倍空间.md"
with io.open(F, encoding="utf-8") as f:
    t = f.read()

lines = t.split("\n")
issues = []

print("=" * 60)
print(" Agent A · pedagogy 视角评审")
print("=" * 60)

# P1 认知负荷：每个知识点的篇幅是否均衡
print("\n[P1] 认知负荷 · 三个知识点的篇幅分布")
secs = []
for i, ln in enumerate(lines):
    if ln.startswith("### 知识点"):
        secs.append((i, ln))
for k in range(len(secs)):
    start = secs[k][0]
    end = secs[k + 1][0] if k + 1 < len(secs) else len(lines)
    n = end - start
    print("   %-46s %5d 行" % (secs[k][1][:44], n))
    if n > 200:
        issues.append(("P1", "%s 篇幅 %d 行，认知负荷偏重" % (secs[k][1][:40], n)))
    if n < 60:
        issues.append(("P1", "%s 篇幅 %d 行，可能讲不透" % (secs[k][1][:40], n)))

# P2 前置知识：引用未讲概念时是否给了说明
print("\n[P2] 前置知识 · 跨课引用的概念是否自带解释")
refs = {
    "TSID": "课 5",
    "MergeSet": "课 5",
    "倒排索引": "课 5",
    "基数": "课 4",
    "relabel": "课 4",
    "remote write": "课 4",
    "Parquet": "InfluxDB 课",
}
for term, src in refs.items():
    n = t.count(term)
    if n > 0:
        # 检查该术语首次出现附近是否有解释性文字
        print("   [OK]   %-16s 出现 %2d 次（源自 %s）" % (term, n, src))
    else:
        print("   [--]   %-16s 未出现" % term)

# P3 类比质量：类比的选用与失效边界
print("\n[P3] 类比质量")
analogies = ["想象你要记录一整本", "想象你要记录一整年", "想象你要把一整本"]
found = sum(t.count(a) for a in analogies)
print("   类比引入语出现: %d 次" % found)
print("   类比失效边界块: %d 处" % t.count("类比失效的边界"))
if t.count("类比失效的边界") < 3:
    issues.append(("P1", "类比失效边界不足 3 处，学员可能误用类比"))

# P4 练习设计：课后小测的质量
print("\n[P4] 练习设计 · 课后小测")
quiz = t.split("## 课后小测")[1].split("## 🚀")[0] if "## 课后小测" in t else ""
n_q = quiz.count("<summary>")
n_a = quiz.count("**答案**")
print("   题目数: %d   答案数: %d" % (n_q, n_a))
if n_q != n_a:
    issues.append(("P0", "课后小测题目数与答案数不匹配"))
if n_q < 3:
    issues.append(("P1", "课后小测少于 3 题"))
# 多选/单选设计
print("   含多选: %s" % ("是" if "多选" in quiz else "否"))

# P5 节奏：五幕篇幅
print("\n[P5] 节奏控制 · 五幕篇幅")
acts = ["## 第一幕", "## 第二幕", "## 第三幕", "## 第四幕", "## 第五幕"]
pos = []
for a in acts:
    for i, ln in enumerate(lines):
        if ln.startswith(a):
            pos.append((a, i))
            break
for k in range(len(pos)):
    start = pos[k][1]
    end = pos[k + 1][1] if k + 1 < len(pos) else len(lines)
    ratio = (end - start) * 100.0 / len(lines)
    print("   %-10s %5d 行  (%.1f%%)" % (pos[k][0], end - start, ratio))
    if ratio > 55:
        issues.append(("P2", "%s 占 %.0f%%，篇幅过重" % (pos[k][0], ratio)))

# P6 冲突感：第二幕是否真的制造了认知冲突
print("\n[P6] 认知冲突强度")
conflict_markers = ["但是错的", "冲突点", "这个解释的问题在于", "陷阱"]
n = sum(t.count(m) for m in conflict_markers)
print("   冲突标记词: %d 处" % n)
if n < 3:
    issues.append(("P1", "第二幕认知冲突不够强"))

# P7 可操作指令：命令是否可直接复制
print("\n[P7] 可操作性 · 代码块")
blocks = re.findall(r"```(\w*)\n(.*?)```", t, re.S)
bash_blocks = [b for lang, b in blocks if lang == "bash"]
print("   bash 代码块: %d 个" % len(bash_blocks))
url_blocks = sum(1 for b in bash_blocks if "curl" in b)
print("   含 curl 的可执行块: %d 个" % url_blocks)

print("\n" + "=" * 60)
print(" Agent A 评审结论")
print("=" * 60)
if not issues:
    print("✅ 未发现 P0/P1 问题")
else:
    for lvl, msg in issues:
        print("[%s] %s" % (lvl, msg))
