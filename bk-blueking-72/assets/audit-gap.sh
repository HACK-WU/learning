#!/usr/bin/env bash
NS=blueking
echo "=== 1. 从未成功启动过的组件（本轮重点补齐对象） ==="
for d in bk-kafka bkiam-search-engine bk-repo-bkrepo-repository bk-repo-bkrepo-maven bk-repo-bkrepo-auth bk-repo-bkrepo-generic bk-repo-bkrepo-docker bk-repo-bkrepo-helm bk-repo-bkrepo-npm bk-repo-bkrepo-pypi bk-repo-bkrepo-opdata bk-repo-bkrepo-replication bk-repo-bkrepo-job; do
  out=$(kubectl get deploy -n $NS $d --no-headers 2>/dev/null)
  if [ -z "$out" ]; then
    # 可能是 statefulset
    out=$(kubectl get sts -n $NS $d --no-headers 2>/dev/null)
    [ -n "$out" ] && echo "  [sts] $d : $(echo $out|awk '{print $2}')"
  else
    echo "  [dep] $d : $(echo $out|awk '{print $2}')"
  fi
done

echo ""
echo "=== 2. kafka 当前状态 ==="
kubectl get pods -n $NS -l app.kubernetes.io/name=kafka --no-headers 2>/dev/null | sed 's/^/  /'
kubectl get pods -n $NS --no-headers 2>/dev/null | grep kafka | sed 's/^/  /'

echo ""
echo "=== 3. bkiam-search-engine (sts) ==="
kubectl get pods -n $NS --no-headers 2>/dev/null | grep 'search-engine' | sed 's/^/  /'

echo ""
echo "=== 4. bk-repo 全量 ==="
kubectl get pods -n $NS --no-headers 2>/dev/null | grep 'bkrepo' | sed 's/^/  /'

echo ""
echo "=== 5. 异常 Pod (Init/Error) ==="
kubectl get pods -n $NS --no-headers 2>/dev/null | awk '$3=="Init:0/1"||$3=="Error"||$3=="CrashLoopBackOff"' | sed 's/^/  /'

echo ""
echo "=== 6. 页面 ==="
for d in paas.example.com bkpaas.paas.example.com bkmonitor.paas.example.com bkrepo.paas.example.com bknodeman.paas.example.com bkiam.paas.example.com apigw.paas.example.com bkcmdb.paas.example.com bkuser.paas.example.com; do
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 "http://$d/" 2>/dev/null)
  printf "  %-32s %s\n" "$d" "$code"
done
