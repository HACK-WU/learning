# -*- coding: utf-8 -*-
"""
课 7 双 agent 评审 · Agent B：learner（学员视角）
核心判据：零上下文读者能否看懂、能否照着做、会不会被坑
"""
import io
import re

F = "/mnt/d/projects/learning/victoriametrics/stages/3-凭什么快凭什么省/7-内存模型与容量规划.md"
with io.open(F, encoding="utf-8") as f:
    t = f.read()

issues = []
print("=" * 60)
print(" Agent B · learner 视角评审")
print("=" * 60)

# L1 环境前置
print("\n[L1] 环境前置")
for kw, desc in [("playground", "工作目录"), ("localhost:8428", "VM 地址"),
                 ("totalSeries", "权威序列数指标")]:
    hit = kw in t
    print("   %s %s" % ("[OK]  " if hit else "[MISS]", desc))
    if not hit:
        issues.append(("P1", "缺少环境前置：%s" % desc))

# L2 判据完整性
print("\n[L2] 可验证性")
exp = t.split("## 第四幕")[1].split("## 第五幕")[0] if "## 第四幕" in t else ""
ne, nj = exp.count("### 实验"), exp.count("**判据**")
print("   实验 %d / 判据 %d" % (ne, nj))
if nj < ne:
    issues.append(("P1", "实验判据不全"))

# L3 踩坑覆盖（本课真实踩过的）
print("\n[L3] 踩坑预警")
pit = t.split("## 🐞 常见误区")[1].split("## 🚀")[0] if "## 🐞 常见误区" in t else ""
print("   误区条数: %d" % pit.count("### "))
must = {
    "平均值": "平均值法误导容量估算",
    "hour_metric_ids": "hour_metric_ids 有 15 秒延迟",
    "虚拟地址": "vm_cache_size_bytes 是虚拟地址",
    "重启": "重启不清空缓存（修正课 5）",
    "计数器": "重启后累计计数器重置",
    "allowedBytes": "容器环境要显式设内存上限",
}
for kw, desc in must.items():
    hit = kw in pit
    print("   %s %s" % ("[OK]  " if hit else "[MISS]", desc))
    if not hit:
        issues.append(("P1", "未记录踩坑：%s" % desc))

# L4 数字时效性标注（本课关键：重启会重置计数器）
print("\n[L4] 数字时效性")
print("   本机实测标注: %d 处" % t.count("本机实测"))
if t.count("本机实测") < 5:
    issues.append(("P2", "关键数字缺少本机实测标注"))

# L5 术语解释
print("\n[L5] 术语解释")
terms = {
    "fastcache": "预分配",
    "RSS": "物理",
    "边际成本": "增量",
    "mmap": "地址空间",
    "hour_metric_ids": "按小时",
}
for term, clue in terms.items():
    hit, exp_ = term in t, clue in t
    print("   %s %-16s 出现=%s 有解释=%s" % ("[OK]  " if (hit and exp_) else "[WARN]", term, hit, exp_))
    if hit and not exp_:
        issues.append(("P2", "术语 %s 缺解释" % term))

# L6 命令自包含
print("\n[L6] 命令自包含性")
blocks = re.findall(r"```bash\n(.*?)```", t, re.S)
print("   bash 块: %d 个" % len(blocks))
vague = [b for b in blocks if "xxx" in b or "TODO" in b]
print("   含占位符: %d 个" % len(vague))

# L7 跨课伏笔闭环（课 6 留下的）
print("\n[L7] 跨课伏笔闭环")
for kw, desc in [("97.5", "回答「凭什么快」"), ("重启", "回答「会不会冷」"),
                 ("边际", "回答「1GB 从哪来」")]:
    hit = kw in t
    print("   %s %s (%s)" % ("[OK]  " if hit else "[MISS]", desc, kw))
    if not hit:
        issues.append(("P1", "未闭环：%s" % desc))

# L8 遗留疑问是否诚实标注
print("\n[L8] 未闭环疑问的诚实标注")
if "尚未闭环" in t or "未闭环" in t or "尚不明确" in t:
    print("   [OK]   课 7 坦承了 data/cache 未自动重建的疑问")
else:
    issues.append(("P2", "未标注已知未闭环的疑问"))

# L9 危险操作是否有警告
print("\n[L9] 危险操作警告")
for kw in ["docker restart", "rm -rf"]:
    if kw in t:
        # 检查附近是否有警告
        idx = t.find(kw)
        ctx = t[max(0, idx - 300):idx + 300]
        warned = "⚠" in ctx or "注意" in ctx or "备份" in ctx
        print("   %s %s 有警告" % ("[OK]  " if warned else "[WARN]", kw))
        if not warned:
            issues.append(("P1", "危险操作 %s 缺少警告" % kw))

print("\n" + "=" * 60)
print(" Agent B 评审结论")
print("=" * 60)
if not issues:
    print("✅ 未发现 P0/P1 问题")
else:
    for lvl, msg in issues:
        print("[%s] %s" % (lvl, msg))
