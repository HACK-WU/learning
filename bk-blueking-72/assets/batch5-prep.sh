#!/usr/bin/env bash
NS=blueking
echo "=== 1. 内存 ==="
free -g | sed -n '2p' | awk '{printf "    used=%sG avail=%sG\n",$3,$7}'

echo ""
echo "=== 2. 日志相关 deploy（bk-log / applog / log） ==="
kubectl get deploy -n $NS --no-headers 2>/dev/null | grep -iE 'log' | awk '{printf "  %-46s %s\n",$1,$2}'

echo ""
echo "=== 3. 日志相关 sts/statefulset ==="
kubectl get sts -n $NS --no-headers 2>/dev/null | grep -iE 'log|es|elastic' | awk '{printf "  %-46s %s\n",$1,$2}'

echo ""
echo "=== 4. 日志依赖：ES / kafka / bk-data ==="
kubectl get pods -n $NS --no-headers 2>/dev/null | grep -iE 'elastic|bk-kafka|bk-data' | awk '{printf "  %-46s %s\n",$1,$3}'

echo ""
echo "=== 5. ingress 中的日志域名 ==="
kubectl get ingress -n $NS 2>/dev/null | grep -iE 'log' | awk '{print "  "$2" "$3}'

echo ""
echo "=== 6. 当前所有 Running 的（看已有基线） ==="
kubectl get pods -n $NS --no-headers 2>/dev/null | awk '$3=="Running"' | wc -l | awk '{print "    Running 总数: "$1}'
