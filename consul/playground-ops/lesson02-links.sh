#!/usr/bin/env bash
python3 - <<'PYEOF'
import os,re
M="/mnt/d/projects/learning/consul/子教程/运维专项/lessons/lesson-02-集群健康与day-2运维.md"
d=os.path.dirname(M)
txt=open(M,encoding='utf-8').read()
rels=sorted(set(re.findall(r'\]\((\.[^)#]+)\)',txt)))
print(f"共 {len(rels)} 条相对链接\n")
for r in rels:
    t=os.path.normpath(os.path.join(d,r))
    print(("  OK   " if os.path.exists(t) else "  DEAD ")+r)
PYEOF
