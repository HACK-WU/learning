#!/usr/bin/env bash
NS=blueking

echo "=== 1. 先确认 pod 真的在跑（不是我 grep 错了） ==="
kubectl get pods -n $NS --no-headers 2>/dev/null | grep -E 'alarm-beat|alarm-detect' | awk '{print "    "$1" "$3" restarts="$4}'

echo ""
echo "=== 2. 直接不带任何过滤看原始 output ==="
kubectl logs -n $NS deploy/bk-monitor-alarm-beat 2>&1 | head -20
echo "  --- exit=$? ---"

echo ""
echo "=== 3. 容器里到底有没有日志文件（判断是不是输出到文件了） ==="
kubectl exec -n $NS deploy/bk-monitor-alarm-beat -- ls -la /app/logs/ 2>&1 | head -10
echo "  --- 若报 no such file，试 /data/logs ---"
kubectl exec -n $NS deploy/bk-monitor-alarm-beat -- ls -la /data/logs/ 2>&1 | head -10

echo ""
echo "=== 4. 看容器启动命令（判断它是什么类型的进程） ==="
kubectl get deploy -n $NS bk-monitor-alarm-beat -o jsonpath='{.spec.template.spec.containers[0].command}' 2>/dev/null | head -c 300
echo ""

echo ""
echo "=== 5. 进程列表 ==="
kubectl exec -n $NS deploy/bk-monitor-alarm-beat -- ps aux 2>&1 | head -10

echo ""
echo "=== 6. probe 用的是什么（无探针的话，怎么判断存活） ==="
kubectl get deploy -n $NS bk-monitor-alarm-beat -o jsonpath='{.spec.template.spec.containers[0]}' 2>/dev/null | head -c 600
echo ""
