#!/usr/bin/env bash
python3 - <<'PYEOF'
import io
p="/mnt/d/projects/learning/consul/01-学习路径总览.md"
s=io.open(p,encoding='utf-8').read()
old="**进度：课 2 / 8 已交付**"
new="**进度：课 3 / 8 已交付**"
assert old in s, "未找到旧进度标记"
s=s.replace(old,new)
old2="[课 2 集群健康与 day-2 运维](子教程/运维专项/lessons/lesson-02-集群健康与day-2运维.md)）"
new2="[课 2 集群健康与 day-2 运维](子教程/运维专项/lessons/lesson-02-集群健康与day-2运维.md)、[课 3 性能、容量与调优](子教程/运维专项/lessons/lesson-03-性能、容量与调优.md)）"
assert old2 in s, "未找到课2链接结尾"
s=s.replace(old2,new2)
io.open(p,'w',encoding='utf-8').write(s)
print("已更新 01-学习路径总览.md")
# 校验
import re
t=io.open(p,encoding='utf-8').read()
for m in re.findall(r'进度：课 \d / 8 已交付',t): print("  ",m)
PYEOF
