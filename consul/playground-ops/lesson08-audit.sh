#!/usr/bin/env bash
python3 - <<'PYEOF'
import re, os
L8 = "/mnt/d/projects/learning/consul/子教程/运维专项/lessons/lesson-08-多机房与K8s运维视角.md"
R  = "/mnt/d/projects/learning/consul"
B  = os.path.dirname(L8)
s  = open(L8, encoding='utf-8').read()

print("===== 独立复审（每条判定先核验）=====")

# 1. 链接
links = re.findall(r'\]\(([^)]+\.md)\)', s)
bad = [l for l in links if not os.path.isfile(os.path.join(B, l.split('#')[0]))]
print(f"  [1] 链接 {len(links)} 条，断链 {len(bad)} 条 {bad if bad else '✅'}")

# 2. 讲义声称的实测数字，是否都在讲义中有实测出处
claims = {
    "40 秒": "WAN故障检测",
    "connection refused": "kill-9报错",
    "No path to datacenter": "leave报错",
    "app/only-dc1": "跨DC键列表",
}
for k, v in claims.items():
    print(f"  [2] 声称 '{k}'({v}) 在讲义中出现 {s.count(k)} 次 {'✅' if s.count(k)>0 else '❌'}")

# 3. 未实测部分是否有标注
k8s_sec = s[s.find('## 二、K8s 上的运维'):s.find('## 三、退出与迁移')]
if '本机未实测' in k8s_sec:
    print("  [3] K8s 章节有未实测标注 ✅")
else:
    print("  [3] ❌ K8s 章节缺未实测标注")

# 4. 官方默认值核对（引自文档，非实测）
for p in ["probe_interval", "5s", "suspicion_mult", "6"]:
    print(f"  [4] 引用默认值 '{p}' 出现 {s.count(p)} 次")

# 5. 结构完整性
for sec in ["## 一、", "## 二、", "## 三、", "## 四、", "## 五、", "### 小测", "<details>"]:
    print(f"  [5] 章节 '{sec}' {'✅' if sec in s else '❌ 缺失'}")

# 6. 小测与答案数量一致
q = len(re.findall(r'^\d\. ', s[s.find('### 小测'):s.find('<details>')], re.M))
a = len(re.findall(r'^\d\. \*\*', s[s.find('<details>'):], re.M))
print(f"  [6] 小测 {q} 题 / 答案 {a} 条 {'✅' if q==a else '❌ 不匹配'}")
PYEOF
