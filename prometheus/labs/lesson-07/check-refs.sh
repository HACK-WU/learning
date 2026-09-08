#!/usr/bin/env bash
L7=/mnt/d/projects/learning/prometheus/labs/lesson-07
echo "=== 讲义引用的脚本/配置文件存在性核验 ==="
MISS=0
for f in setup.sh setup-rr.sh setup-reader.sh setup-backend2.sh setup-agent.sh \
         fair-compare.sh final-compare.sh verify-part4-b.sh review-check.sh \
         app/receiver.py app/app.py app/Dockerfile app/Dockerfile.app \
         l7lib.py agent-record-only.yml rules-record-only.yml agent.yml prometheus.yml; do
  if [ -e "$L7/$f" ]; then
    echo "  OK    $f"
  else
    echo "  MISS  $f"
    MISS=$((MISS+1))
  fi
done
echo
echo "缺失数 = $MISS"
