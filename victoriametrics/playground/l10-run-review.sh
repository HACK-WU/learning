#!/bin/bash
# 课 10 双 agent 评审汇总
cd /mnt/d/projects/learning/victoriametrics/playground || exit 1
echo "########## Agent A · pedagogy 视角 ##########"
python3 l10-review-pedagogy.py 2>&1 | tail -30
echo
echo "########## Agent B · learner 视角 ##########"
python3 l10-review-learner.py 2>&1 | tail -36
