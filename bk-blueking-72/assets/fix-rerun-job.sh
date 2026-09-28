#!/usr/bin/env bash
# 修正版：清洗 selector + template labels（Job 的 controller-uid 必须自洽）
set -uo pipefail
NS=blueking
J=bkpaas3-apiserver-migrate-db-1

echo "===== 用备份重建（保留原 command/args/env）====="
BAK=$(ls -d /root/bk72/install/bk-job-backup-* 2>/dev/null | tail -1)
echo "  备份源: $BAK"

if [ ! -f "$BAK/$J.yaml" ]; then echo "  备份缺失，终止"; exit 1; fi

python3 - "$BAK/$J.yaml" <<'PY'
import json,sys,yaml
d = yaml.safe_load(open(sys.argv[1]))
m = d['metadata']
for k in ['uid','resourceVersion','creationTimestamp','generation','managedFields','ownerReferences','selfLink','namespace','annotations']:
    m.pop(k, None)
d.pop('status', None)
spec = d['spec']
# 关键：selector 和 template labels 要么都删（让 k8s 自动生成），要么保持一致
spec.pop('selector', None)
spec['backoffLimit'] = 1
spec.pop('ttlSecondsAfterFinished', None)
t = spec['template']['metadata']
for k in ['creationTimestamp','managedFields','ownerReferences']:
    t.pop(k, None)
# 去掉 controller-uid（这个必须删，否则与自动生成的 uid 冲突）
if 'labels' in t:
    t['labels'].pop('batch.kubernetes.io/controller-uid', None)
    t['labels'].pop('controller-uid', None)
json.dump(d, open('/tmp/j-fixed.json','w'))
print("  已生成 /tmp/j-fixed.json (selector 交由 k8s 自动生成)")
PY

kubectl apply -f /tmp/j-fixed.json -n $NS 2>&1 | sed 's/^/  /'

echo ""
echo "===== 等 20s 看新 Pod ====="
sleep 20
kubectl get pods -n $NS --no-headers 2>/dev/null | grep "$J" | awk '{printf "  %-46s %-14s 重启%s\n", $1, $3, $4}'

echo ""
echo "===== 新 Pod 日志（真实报错）====="
P=$(kubectl get pods -n $NS --no-headers 2>/dev/null | grep "^$J" | awk '{print $1}' | head -1)
if [ -n "$P" ]; then
  echo "  Pod: $P"
  kubectl logs $P -n $NS --tail=45 2>&1 | sed 's/^/    /'
else
  echo "  无 Pod"
fi
