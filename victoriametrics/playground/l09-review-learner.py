# -*- coding: utf-8 -*-
"""
课 9 双 agent 评审 · Agent B：learner（学员视角）
核心判据：零上下文读者能否看懂、能否照着做、会不会被坑
"""
import io
import re

F = "/mnt/d/projects/learning/victoriametrics/stages/4-怎么横向扩展/9-复制去重与高可用.md"
with io.open(F, encoding="utf-8") as f:
    t = f.read()

issues = []
print("=" * 60)
print(" Agent B · learner 视角评审")
print("=" * 60)

print("\n[L1] 环境前置")
for kw, desc in [("playground", "工作目录"), ("vm-cluster-net", "Docker 网络"),
                 ("v1.151.0-cluster", "镜像版本"), ("8485", "逐节点验证端口")]:
    hit = kw in t
    print("   %s %s" % ("[OK]  " if hit else "[MISS]", desc))
    if not hit:
        issues.append(("P1", "缺少环境前置：%s" % desc))

print("\n[L2] 可验证性")
exp = t.split("## 第四幕")[1].split("## 第五幕")[0] if "## 第四幕" in t else ""
ne, nj = exp.count("### 实验"), exp.count("**判据**")
print("   实验 %d / 判据 %d" % (ne, nj))
if nj < ne:
    issues.append(("P1", "实验判据不全"))

print("\n[L3] 踩坑覆盖（本课真实踩过的）")
pit = t.split("## 🐞 常见误区")[1].split("## 🚀")[0] if "## 🐞 常见误区" in t else ""
print("   误区条数: %d" % pit.count("### "))
must = {
    "dedup": "副本必须配 dedup",
    "5s": "dedup 间隔必须等于采集间隔",
    "10~20 秒": "容器刚启动别急着写",
    "204": "副本失败仍返回成功",
    "不自动补齐": "副本缺口不修复",
    "3 节点": "2 节点配 RF=2 不够",
    "vminsert": "RF 配在 vminsert 不是 vmstorage",
    "重启": "RF 不支持热更新",
}
for kw, desc in must.items():
    hit = kw in pit
    print("   %s %s" % ("[OK]  " if hit else "[MISS]", desc))
    if not hit:
        issues.append(("P1", "未记录踩坑：%s" % desc))

print("\n[L4] 数字时效性标注")
print("   本机实测标注: %d 处" % t.count("本机实测"))
if t.count("本机实测") < 5:
    issues.append(("P2", "关键数字缺少本机实测标注"))

print("\n[L5] 术语解释")
terms = {
    "replicationFactor": "副本",
    "dedup.minScrapeInterval": "窗口",
    "shared-nothing": "互不通信",
    "rerouting": "重路由",
    "best-effort": "尽力而为",
}
for term, clue in terms.items():
    hit, exp_ = term in t, clue in t
    print("   %s %-28s 出现=%-5s 有解释=%s" % ("[OK]  " if (hit and exp_) else "[WARN]", term, hit, exp_))
    if hit and not exp_:
        issues.append(("P2", "术语 %s 缺解释" % term))

print("\n[L6] 命令自包含性")
blocks = re.findall(r"```bash\n(.*?)```", t, re.S)
print("   bash 块: %d 个" % len(blocks))
vague = [b for b in blocks if "xxx" in b or "TODO" in b or "<placeholder>" in b]
print("   含占位符: %d 个" % len(vague))

print("\n[L7] 跨课伏笔闭环（课 8 遗留）")
for kw, desc in [("509", "课 8 静默降级"), ("1000", "课 8 分片基线"),
                 ("课 8", "明确对照上一课")]:
    hit = kw in t
    print("   %s %s (%s)" % ("[OK]  " if hit else "[MISS]", desc, kw))
    if not hit:
        issues.append(("P1", "未闭环：%s" % desc))

print("\n[L8] 危险操作警告")
for kw in ["docker stop", "docker rm -f"]:
    if kw in t:
        idx = t.find(kw)
        ctx = t[max(0, idx - 500):idx + 500]
        warned = "⚠" in ctx or "注意" in ctx or "生产" in ctx
        print("   %s %s 有上下文说明" % ("[OK]  " if warned else "[WARN]", kw))
        if not warned:
            issues.append(("P2", "操作 %s 缺少上下文说明" % kw))

print("\n[L9] 与课 8 的对照是否明确")
seg = t[t.find("## 第五幕"):] if "## 第五幕" in t else t
has_table = "课 8（RF=1" in t or "对照课 8" in t or "1000 → 509" in t
print("   %s 有课 8/课 9 对照" % ("[OK]  " if has_table else "[MISS]"))
if not has_table:
    issues.append(("P1", "缺少与课 8 的对照数据"))

print("\n" + "=" * 60)
print(" Agent B 评审结论")
print("=" * 60)
if not issues:
    print("✅ 未发现 P0/P1 问题")
else:
    for lvl, msg in issues:
        print("[%s] %s" % (lvl, msg))
