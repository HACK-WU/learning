#!/bin/bash
cd /mnt/d/projects/learning/victoriametrics/playground
echo "===== AGENT A: PEDAGOGY 视角 ====="
python3 l11-review-pedagogy.py 2>&1 | head -75
echo
echo "===== AGENT B: LEARNER 视角 ====="
python3 l11-review-learner.py 2>&1 | head -80
