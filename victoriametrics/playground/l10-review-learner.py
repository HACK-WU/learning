# -*- coding: utf-8 -*-
"""
课 10 双 agent 评审 · Agent B：learner（学员视角）
核心判据：零上下文读者能否看懂、能否照着做、会不会被坑
"""
import io
import re

F = "/mnt/d/projects/learning/victoriametrics/stages/4-怎么横向扩展/10-多租户与vmauth.md"
with io.open(F, encoding="utf-8") as f:
    t = f.read()

issues = []
print("=" * 60)
print(" Agent B · learner 视角评审")
print("=" * 60)

print("\n[L1] 环境前置")
for kw, desc in [("playground", "工作目录"), ("vm-cluster-net", "Docker 网络"),
                 ("v1.151.0", "镜像版本"), ("8427", "vmauth 端口")]:
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
    "prometheus": "url_prefix 缺协议段",
    "influx": "协议风格错配",
    "静默进 tenant 0": "空租户 ID 不报错",
    "7.4 倍": "资源不隔离",
    "零 429": "快查询触发不了限流",
    "通配": "src_paths 不能图省事",
    "reload": "热重载无需重启",
    "/write": "单节点与集群路径差异",
    "按租户拆分": "无法查每租户资源用量",
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
    "src_paths": "客户端路径",
    "url_prefix": "后端地址前缀",
    "least_loaded": "最少连接",
    "maxConcurrentPerUserRequests": "并发",
    "hot reload": "热重载",
}
for term, clue in terms.items():
    hit, exp_ = term in t, clue in t
    print("   %s %-32s 出现=%-5s 有解释=%s" % ("[OK]  " if (hit and exp_) else "[WARN]", term, hit, exp_))
    if hit and not exp_:
        issues.append(("P2", "术语 %s 缺解释" % term))

print("\n[L6] 命令自包含性")
blocks = re.findall(r"```bash\n(.*?)```", t, re.S)
print("   bash 块: %d 个" % len(blocks))
vague = [b for b in blocks if "xxx" in b or "TODO" in b or "<placeholder>" in b]
print("   含占位符: %d 个" % len(vague))

print("\n[L7] 与课 8/课 9 的承接")
for kw, desc in [("课 8", "承接课 8"), ("课 9", "承接课 9"),
                 ("RF=2", "课 9 的副本")]:
    hit = kw in t
    print("   %s %s (%s)" % ("[OK]  " if hit else "[MISS]", desc, kw))
    if not hit:
        issues.append(("P1", "未承接：%s" % desc))

print("\n[L8] 危险操作警告")
for kw in ["docker stop", "docker rm -f"]:
    if kw in t:
        idx = t.find(kw)
        ctx = t[max(0, idx - 800):idx + 800]
        warned = "⚠" in ctx or "注意" in ctx or "生产" in ctx
        print("   %s %s 有上下文说明" % ("[OK]  " if warned else "[WARN]", kw))
        if not warned:
            issues.append(("P2", "操作 %s 缺少上下文说明" % kw))

print("\n[L9] 关键认知：数据隔离 vs 资源隔离")
core = "7.4 倍" in t and "10932" in t and "0.001792" in t
print("   %s 坏邻居效应有量化证据" % ("[OK]  " if core else "[MISS]"))
if not core:
    issues.append(("P0", "缺少坏邻居效应的量化证据"))

print("\n[L10] 限流的三轮失败是否有记录")
rounds = "第 1 轮" in t and "第 2 轮" in t and "第 3 轮" in t
print("   %s 三轮压测对比" % ("[OK]  " if rounds else "[MISS]"))
if not rounds:
    issues.append(("P1", "未记录三轮压测对比，学员会重复踩坑"))

print("\n" + "=" * 60)
print(" Agent B 评审结论")
print("=" * 60)
if not issues:
    print("✅ 未发现 P0/P1 问题")
else:
    for lvl, msg in issues:
        print("[%s] %s" % (lvl, msg))
