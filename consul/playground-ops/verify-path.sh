#!/usr/bin/env bash
python3 - <<'PYEOF'
import os
base="/mnt/d/projects/learning/consul/子教程/运维专项/lessons"
rels=[
 "../../stages/1-认识Consul/lessons/lesson-03-五分钟跑起来看一眼.md",
 "../../../stages/1-认识Consul/lessons/lesson-03-五分钟跑起来看一眼.md",
 "../../stages/2-核心能力拆解/lessons/lesson-05-Raft与Gossip一致性成色.md",
 "../../../stages/2-核心能力拆解/lessons/lesson-05-Raft与Gossip一致性成色.md",
 "../../stages/4-决策落地/lessons/lesson-11-许可证成本与风险.md",
 "../../../stages/4-决策落地/lessons/lesson-11-许可证成本与风险.md",
]
for r in rels:
    p=os.path.normpath(os.path.join(base,r))
    print(("OK   " if os.path.exists(p) else "DEAD "), r)
print()
print("lesson dir exists:", os.path.isdir(base))
print("stages at ../../../stages:", os.path.isdir("/mnt/d/projects/learning/consul/stages"))
PYEOF
