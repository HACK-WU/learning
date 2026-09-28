#!/usr/bin/env bash
NS=blueking
echo "=== STEP 1: 提前放宽 bk-repo 各组件探针（防 opdata 重演） ==="
for d in bk-repo-bkrepo-auth bk-repo-bkrepo-gateway bk-repo-bkrepo-repository \
         bk-repo-bkrepo-generic bk-repo-bkrepo-docker bk-repo-bkrepo-helm \
         bk-repo-bkrepo-maven bk-repo-bkrepo-npm bk-repo-bkrepo-pypi \
         bk-repo-bkrepo-opdata bk-repo-bkrepo-job bk-repo-bkrepo-replication; do
  # 取容器名
  CN=$(kubectl get deploy -n $NS $d -o jsonpath='{.spec.template.spec.containers[0].name}' 2>/dev/null)
  [ -z "$CN" ] && continue
  # 判断有无 livenessProbe
  HAS=$(kubectl get deploy -n $NS $d -o json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
c=d['spec']['template']['spec']['containers'][0]
print('yes' if c.get('livenessProbe') else 'no')
" 2>/dev/null)
  if [ "$HAS" == "yes" ]; then
    kubectl patch deploy -n $NS $d --type='json' -p='[
      {"op":"replace","path":"/spec/template/spec/containers/0/livenessProbe/initialDelaySeconds","value":180},
      {"op":"replace","path":"/spec/template/spec/containers/0/livenessProbe/failureThreshold","value":12}
    ]' >/dev/null 2>&1 && echo "  [放宽] $d"
  else
    echo "  [无探针] $d"
  fi
done

echo ""
echo "=== STEP 2: 起核心 4 个（auth → gateway → repository → generic） ==="
kubectl scale deploy -n $NS bk-repo-bkrepo-auth --replicas=1 >/dev/null 2>&1 && echo "  [起] auth"
sleep 45
kubectl scale deploy -n $NS bk-repo-bkrepo-gateway --replicas=1 >/dev/null 2>&1 && echo "  [起] gateway"
sleep 45
kubectl scale deploy -n $NS bk-repo-bkrepo-repository --replicas=1 >/dev/null 2>&1 && echo "  [起] repository"
sleep 45
kubectl scale deploy -n $NS bk-repo-bkrepo-generic --replicas=1 >/dev/null 2>&1 && echo "  [起] generic"

echo ""
echo "=== STEP 3: 等 90s ==="
sleep 90

echo ""
echo "=== STEP 4: 状态 ==="
for d in bk-repo-bkrepo-auth bk-repo-bkrepo-gateway bk-repo-bkrepo-repository bk-repo-bkrepo-generic; do
  kubectl get deploy -n $NS $d --no-headers 2>/dev/null | awk '{printf "  %-40s %s\n",$1,$2}'
done

echo ""
echo "=== STEP 5: 内存 ==="
free -g | sed -n '2p' | awk '{printf "    used=%sG avail=%sG\n",$3,$7}'
