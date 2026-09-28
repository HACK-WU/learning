#!/usr/bin/env bash
# 精确抓 Job Pod 每个容器的退出码
set -uo pipefail
NS=blueking
J=bkpaas3-apiserver-migrate-db-1
BAK=$(ls -d /root/bk72/install/bk-job-backup-* 2>/dev/null | tail -1)

kubectl delete job $J -n $NS --wait=false >/dev/null 2>&1
sleep 3
python3 - "$BAK/$J.yaml" <<'PY'
import json,sys,yaml
d = yaml.safe_load(open(sys.argv[1]))
for k in ['uid','resourceVersion','creationTimestamp','generation','managedFields','ownerReferences','selfLink','namespace','annotations']:
    d['metadata'].pop(k, None)
d.pop('status', None)
s=d['spec']; s.pop('selector',None); s['backoffLimit']=1
s.pop('ttlSecondsAfterFinished',None)
t=s['template']['metadata']
for k in ['creationTimestamp','managedFields','ownerReferences']: t.pop(k,None)
if 'labels' in t:
    t['labels'].pop('batch.kubernetes.io/controller-uid',None)
    t['labels'].pop('controller-uid',None)
json.dump(d, open('/tmp/j9.json','w'))
PY
kubectl apply -f /tmp/j9.json -n $NS >/dev/null 2>&1

echo "高频轮询容器状态..."
for i in $(seq 1 150); do
  MP=$(kubectl get pods -n $NS --no-headers 2>/dev/null | grep "^$J" | awk '{print $1}' | head -1)
  if [ -n "$MP" ]; then
    # 持续打印状态直到 Pod 消失
    for k in $(seq 1 100); do
      ST=$(kubectl get pod $MP -n $NS -o jsonpath='{range .status.containerStatuses[*]}{.name}{"|"}{.state.terminated.exitCode}{"|"}{.state.waiting.reason}{"|"}{.state.running}{"\n"}{end}' 2>/dev/null)
      if [ -n "$ST" ]; then
        echo "--- 第${k}轮 ---"
        echo "$ST" | sed 's/^/  /'
        # 有任一容器非0退出立即打印日志
        echo "$ST" | grep -qE '\|[1-9]\|' && {
          echo "  >>> 发现失败容器:"
          for CN in $(echo "$ST" | grep -E '\|[1-9]\|' | cut -d'|' -f1); do
            echo "  ===== $CN 日志 ====="
            kubectl logs $MP -n $NS -c $CN 2>&1 | grep -viE 'InsecureKey|Deprecat|warnings.warn|_jws|return self|fields\.E|fields\.W|HINT' | tail -25 | sed 's/^/    /'
          done
          exit 0
        }
        echo "$ST" | grep -qE '\|0\|' && echo "  (有容器成功)"
      fi
      sleep 2
    done
    break
  fi
  sleep 1
done
echo "未捕获到失败容器"
