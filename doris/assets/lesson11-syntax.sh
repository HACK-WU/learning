#!/bin/bash
# 课 11：交付脚本语法检查
cd /mnt/d/projects/learning/doris/assets
for f in lesson11-setup.sh lesson11-step1.sh lesson11-step2.sh lesson11-step3.sh lesson11-cleanup.sh lesson11-verify.sh lesson11-linkcheck.sh; do
  if [ -f "$f" ]; then
    if bash -n "$f" 2>/tmp/e; then
      echo "[OK]   $f"
    else
      echo "[FAIL] $f"
      cat /tmp/e
    fi
  else
    echo "[SKIP] $f (不存在)"
  fi
done
