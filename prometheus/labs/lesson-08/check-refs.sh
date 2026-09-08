#!/usr/bin/env bash
L8=/mnt/d/projects/learning/prometheus/labs/lesson-08
echo "=== 讲义引用的脚本/配置文件存在性核验 ==="
MISS=0
for f in setup.sh setup-am-cluster.sh \
         probe-federation.sh probe-honor-labels.sh probe-vm-dedup.sh probe-vm-dedup2.sh \
         probe-webhook.sh diag-am.sh diag-global.py probe-rate-diff.sh \
         exp1-federate-type.py exp1-b.py exp2-conflict.py exp2-b.py \
         exp3-ha-dedup.py exp4-no-replica.sh exp5-dedup-cost.sh \
         exp6-gossip-decisive.sh exp7-external-labels.sh \
         verify-part4.sh review-check.sh check-refs.sh \
         app/app.py app/Dockerfile app/webhook_receiver.py app/Dockerfile.webhook \
         leaf-a.yml leaf-b.yml replica-1.yml replica-2.yml \
         global.yml global-nohonor.yml norep-1.yml norep-2.yml \
         alertmanager-1.yml alertmanager-2.yml DATA.md; do
  if [ -e "$L8/$f" ]; then
    echo "  OK    $f"
  else
    echo "  MISS  $f"
    MISS=$((MISS+1))
  fi
done
echo
echo "缺失数 = $MISS"
