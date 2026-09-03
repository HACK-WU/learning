# -*- coding: utf-8 -*-
"""
课 8 双 agent 评审 · Agent B：learner（学员视角）
核心判据：零上下文读者能否看懂、能否照着做、会不会被坑
"""
import io
import re

F = "/mnt/d/projects/learning/victoriametrics/stages/4-怎么横向扩展/8-集群三件套与最小集群实战.md"
with io.open(F, encoding="utf-8") as f:
    t = f.read()

issues = []
print("=" * 60)
print(" Agent B · learner 视角评审")
print("=" * 60)

# L1 环境前置
print("\n[L1] 环境前置")
for kw, desc in [("playground", "工作目录"), ("vm-cluster-net", "Docker 网络"),
                 ("v1.151.0-cluster", "镜像版本"), ("cluster-data", "数据目录")]:
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
    "8482": "vmstorage 不直接对外提供读写",
    "迁移": "扩容后旧数据不迁移",
    "storageDataPath": "数据目录必须独立",
    "7:9": "projectID 是平级标识",
    "vm_account_id": "标签需 multitenant 端点",
    "count()": "验证历史数据别用 count()",
    "资源隔离": "多租户不等于资源隔离",
}
for kw, desc in must.items():
    hit = kw in pit
    print("   %s %s" % ("[OK]  " if hit else "[MISS]", desc))
    if not hit:
        issues.append(("P1", "未记录踩坑：%s" % desc))

# L4 数字时效性标注
print("\n[L4] 数字时效性")
print("   本机实测标注: %d 处" % t.count("本机实测"))
if t.count("本机实测") < 5:
    issues.append(("P2", "关键数字缺少本机实测标注"))

# L5 术语解释
print("\n[L5] 术语解释")
terms = {
    "一致性哈希": "环",
    "shared-nothing": "互不通信",
    "accountID": "租户",
    "vminsert": "写入代理",
    "vmselect": "聚合",
    "复制因子": "课 9",
}
for term, clue in terms.items():
    hit, exp_ = term in t, clue in t
    print("   %s %-16s 出现=%-5s 有解释=%s" % ("[OK]  " if (hit and exp_) else "[WARN]", term, hit, exp_))
    if hit and not exp_:
        issues.append(("P2", "术语 %s 缺解释" % term))

# L6 命令自包含
print("\n[L6] 命令自包含性")
blocks = re.findall(r"```bash\n(.*?)```", t, re.S)
print("   bash 块: %d 个" % len(blocks))
vague = [b for b in blocks if "xxx" in b or "TODO" in b or "<placeholder>" in b]
print("   含占位符: %d 个" % len(vague))
# 检查$PWD 这类变量是否有说明
pwd_used = sum(1 for b in blocks if "$PWD" in b)
print("   使用 \$PWD 的块: %d 个（需在正文说明工作目录）" % pwd_used)

# L7 跨课伏笔闭环（课 7 留下的）
print("\n[L7] 跨课伏笔闭环")
for kw, desc in [("1000 万", "课 7 遗留：单节点上限"), ("1 GB", "课 7 容量数据"),
                 ("65.5", "课 7 边际成本")]:
    hit = kw in t
    print("   %s %s (%s)" % ("[OK]  " if hit else "[MISS]", desc, kw))
    if not hit:
        issues.append(("P1", "未闭环：%s" % desc))

# L8 危险操作警告
print("\n[L8] 危险操作警告")
for kw in ["docker rm -f", "docker stop", "docker restart"]:
    if kw in t:
        idx = t.find(kw)
        ctx = t[max(0, idx - 400):idx + 400]
        warned = "⚠" in ctx or "注意" in ctx or "生产" in ctx or "重启" in ctx
        print("   %s %s 有上下文说明" % ("[OK]  " if warned else "[WARN]", kw))
        if not warned:
            issues.append(("P2", "操作 %s 缺少上下文说明" % kw))

# L9 选型指导是否可操作
print("\n[L9] 选型指导可操作性")
if "什么时候该上集群" in t:
    seg = t.split("什么时候该上集群")[1][:1500]
    has_signal = "✓" in seg or "⚠" in seg or "活跃序列" in seg
    print("   %s 含明确信号清单" % ("[OK]  " if has_signal else "[WARN]"))
    if not has_signal:
        issues.append(("P2", "选型清单缺少可判定的信号"))
else:
    issues.append(("P1", "缺少选型指导"))

print("\n" + "=" * 60)
print(" Agent B 评审结论")
print("=" * 60)
if not issues:
    print("✅ 未发现 P0/P1 问题")
else:
    for lvl, msg in issues:
        print("[%s] %s" % (lvl, msg))
