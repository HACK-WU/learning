#!/usr/bin/env bash
NS=blueking
echo "=== STEP 1: 起 opdata（之前 CrashLoopBackOff 的，探针已放宽） ==="
kubectl scale deploy -n $NS bk-repo-bkrepo-opdata --replicas=1 >/dev/null 2>&1 && echo "  [起] opdata"
sleep 60
kubectl get deploy -n $NS bk-repo-bkrepo-opdata --no-headers 2>/dev/null | awk '{printf "  %-40s %s\n",$1,$2}'

echo ""
echo "=== STEP 2: 起三种典型制品格式（docker/maven/helm） ==="
kubectl scale deploy -n $NS bk-repo-bkrepo-docker --replicas=1 >/dev/null 2>&1 && echo "  [起] docker"
sleep 40
kubectl scale deploy -n $NS bk-repo-bkrepo-maven --replicas=1 >/dev/null 2>&1 && echo "  [起] maven"
sleep 40
kubectl scale deploy -n $NS bk-repo-bkrepo-helm --replicas=1 >/dev/null 2>&1 && echo "  [起] helm"
sleep 60

echo ""
echo "=== STEP 3: 状态 ==="
for d in bk-repo-bkrepo-opdata bk-repo-bkrepo-docker bk-repo-bkrepo-maven bk-repo-bkrepo-helm; do
  kubectl get deploy -n $NS $d --no-headers 2>/dev/null | awk '{printf "  %-40s %s\n",$1,$2}'
done

echo ""
echo "=== STEP 4: 起剩余（job / replication / npm / pypi） ==="
for d in bk-repo-bkrepo-job bk-repo-bkrepo-replication bk-repo-bkrepo-npm bk-repo-bkrepo-pypi; do
  kubectl scale deploy -n $NS $d --replicas=1 >/dev/null 2>&1 && echo "  [起] $d"
  sleep 30
done

echo ""
echo "=== STEP 5: 等 90s 全量就绪 ==="
sleep 90

echo ""
echo "=== STEP 6: bk-repo 全量状态 ==="
kubectl get deploy -n $NS --no-headers 2>/dev/null | grep '^bk-repo' | awk '{printf "  %-46s %s\n",$1,$2}'

echo ""
echo "=== STEP 7: 未就绪的 ==="
kubectl get pods -n $NS --no-headers 2>/dev/null | grep bkrepo | awk '$3!="Running"{print "  [未就绪] "$1" "$3}'
echo "  (空=全好)"

echo ""
echo "=== STEP 8: 内存 ==="
free -g | sed -n '2p' | awk '{printf "    used=%sG avail=%sG\n",$3,$7}'
