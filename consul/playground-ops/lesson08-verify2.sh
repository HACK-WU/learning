#!/usr/bin/env bash
python3 - <<'PYEOF'
import re
L8 = "/mnt/d/projects/learning/consul/子教程/运维专项/lessons/lesson-08-多机房与K8s运维视角.md"
s = open(L8, encoding='utf-8').read()
q_sec = s[s.find('### 小测'):s.find('<details>')]
a_sec = s[s.find('<details>'):]
q = re.findall(r'^(\d+)\. ', q_sec, re.M)
a = re.findall(r'^(\d+)\. ', a_sec, re.M)
print(f"  题目编号: {q}")
print(f"  答案编号: {a}")
print(f"  >>> {len(q)} 题 / {len(a)} 答案  {'✅ 匹配' if len(q)==len(a) and q==a else '❌ 不匹配'}")
PYEOF
