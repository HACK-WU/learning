#!/bin/bash
# 课 6 双 agent 评审汇总执行
cd /mnt/d/projects/learning/victoriametrics/playground || exit 1
echo "########## Agent A · pedagogy 视角 ##########"
python3 l06-review-pedagogy.py 2>&1 | tail -20
echo
echo "########## Agent B · learner 视角 ##########"
python3 l06-review-learner.py 2>&1 | tail -32
