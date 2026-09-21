#!/usr/bin/env bash
L8="/mnt/d/projects/learning/consul/子教程/运维专项/lessons/lesson-08-多机房与K8s运维视角.md"
echo "===== 答案区真实内容（前 20 行）====="
awk '/<details>/,0' "$L8" | head -20 | cat -n | sed 's/^/  /'
