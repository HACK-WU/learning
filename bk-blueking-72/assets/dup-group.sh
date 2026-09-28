#!/usr/bin/env bash
NS=blueking
echo "=== SAAS/WEB 三件套重复 (api-web / saas-web / web) ==="
kubectl get deploy -n $NS --no-headers 2>/dev/null | awk '$1 ~ /(saas-web|saas-api|-web|webfe|web-fe)/ {print "  "$1}' | sort
echo ""
echo "=== 各类 worker / beat / celery 数量 ==="
echo "  worker类:  $(kubectl get deploy -n $NS --no-headers 2>/dev/null | awk '$1 ~ /worker|pworker/' | wc -l)"
echo "  beat类:    $(kubectl get deploy -n $NS --no-headers 2>/dev/null | awk '$1 ~ /beat|celery/' | wc -l)"
echo "  cron类:    $(kubectl get deploy -n $NS --no-headers 2>/dev/null | awk '$1 ~ /cron/' | wc -l)"
echo ""
echo "=== 当前 READY=0 的 deploy (已经没跑起来的) ==="
kubectl get deploy -n $NS --no-headers 2>/dev/null | awk '$3=="0" {print "  "$1}' | sort | tee /tmp/dead.txt | wc -l
echo ""
echo "=== 这些 dead deploy 的 requests/limits 总和 ==="
TOT_MEM=0; TOT_CPU=0
for d in $(cat /tmp/dead.txt); do
  M=$(kubectl get deploy "$d" -n $NS -o jsonpath='{.spec.template.spec.containers[*].resources.requests.memory}' 2>/dev/null)
  echo "    $d : ${M:-<none>}"
done
