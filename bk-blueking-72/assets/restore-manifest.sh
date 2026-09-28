#!/usr/bin/env bash
NS=blueking

echo "=== 1. kafka: managedFields 看谁改了探针 ==="
kubectl get sts -n $NS bk-kafka -o json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
for mf in d['metadata'].get('managedFields',[]):
    print('  manager:', mf.get('manager'), '| operation:', mf.get('operation'))
" 2>&1 | head -8

echo ""
echo "=== 2. kafka: 对比 helm release 里的原始 manifest（最权威） ==="
helm get manifest bk-kafka -n $NS 2>/dev/null | grep -B4 -A10 'livenessProbe' | head -30

echo ""
echo "=== 3. bkrepo: helm release 原始 manifest 里的探针 ==="
helm get manifest bk-repo -n $NS 2>/dev/null | grep -A9 'livenessProbe' | head -20

echo ""
echo "=== 4. bkrepo: 原始 manifest 的 readiness ==="
helm get manifest bk-repo -n $NS 2>/dev/null | grep -A9 'readinessProbe' | head -16

echo ""
echo "=== 5. 我改过哪些（kubectl patch 历史无法查，看报告记录） ==="
grep -rn -E 'initialDelaySeconds.*180|180.*initialDelay|patch.*probe|probe.*patch' \
  /mnt/d/projects/learning/bk-blueking-72/*.md /mnt/d/projects/learning/bk-blueking-72/assets/*.sh 2>/dev/null \
  | grep -v '00-学习档案\|08-实战\|09-排障' | head -10
