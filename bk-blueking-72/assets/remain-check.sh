#!/usr/bin/env bash
NS=blueking

echo "=== 1. 所有 0/0 的 Deployment（未启动的） ==="
kubectl get deploy -n $NS --no-headers 2>/dev/null | awk '$2=="0/0"{print $1}' | sort

echo ""
echo "=== 2. 所有 0/0 的 StatefulSet ==="
kubectl get sts -n $NS --no-headers 2>/dev/null | awk '$2=="0/0"{print $1}' | sort

echo ""
echo "=== 3. 按所属 helm release 归类（看属于哪条链路） ==="
helm list -n $NS --short 2>/dev/null | while read r; do
  cnt=$(kubectl get deploy,sts -n $NS -l "app.kubernetes.io/instance=$r" --no-headers 2>/dev/null | awk '$2=="0/0"' | wc -l)
  tot=$(kubectl get deploy,sts -n $NS -l "app.kubernetes.io/instance=$r" --no-headers 2>/dev/null | wc -l)
  [ "$cnt" -gt 0 ] && printf "  %-24s 未启动 %-3s / 共 %s\n" "$r" "$cnt" "$tot"
done

echo ""
echo "=== 4. 这些未启动的属于什么类型（worker/beat/其他） ==="
kubectl get deploy,sts -n $NS --no-headers 2>/dev/null | awk '$2=="0/0"{print $1}' | sed 's/.*bk-//' | \
  sed -E 's/.*(worker|beat|celery|sync|cron|job|consumer).*/\1/;t;c other' | sort | uniq -c | sort -rn

echo ""
echo "=== 5. 当前 1/1 在跑的有多少 ==="
kubectl get deploy -n $NS --no-headers 2>/dev/null | awk '$2!="0/0"' | wc -l | xargs echo "  deploy 在跑:"
kubectl get sts -n $NS --no-headers 2>/dev/null | awk '$2!="0/0"' | wc -l | xargs echo "  sts 在跑:"
