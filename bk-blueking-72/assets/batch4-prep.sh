#!/usr/bin/env bash
NS=blueking
echo "=== 1. 内存 ==="
free -g | sed -n '1,2p'

echo ""
echo "=== 2. bk-repo 全部 deploy 及当前副本 ==="
kubectl get deploy -n $NS --no-headers 2>/dev/null | grep '^bk-repo' | awk '{printf "  %-46s %s\n",$1,$2}'

echo ""
echo "=== 3. bkpaas3-svc-bkrepo 相关 ==="
kubectl get deploy -n $NS --no-headers 2>/dev/null | grep 'bkrepo' | awk '{printf "  %-46s %s\n",$1,$2}'

echo ""
echo "=== 4. bk-repo 依赖的存储（mongodb/redis 是否在跑） ==="
kubectl get pods -n $NS --no-headers 2>/dev/null | grep -E 'bk-mongodb|bk-redis|bk-mysql8' | awk '{printf "  %-46s %s\n",$1,$3}'

echo ""
echo "=== 5. bk-repo gateway 的 ingress / svc ==="
kubectl get svc -n $NS 2>/dev/null | grep bkrepo | head -10
kubectl get ingress -n $NS 2>/dev/null | grep -i repo | head -5

echo ""
echo "=== 6. 未就绪 Pod 总数 ==="
kubectl get pods -n $NS --no-headers 2>/dev/null | awk '$3!="Running" && $3!="Completed"{print "  "$1" "$3}'
echo "  (空=全好)"
