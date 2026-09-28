#!/usr/bin/env bash
set -uo pipefail
NS=blueking

echo "===== 1. 实际在跑的 Deployment（不看 helm 状态，看真实 Pod）====="
kubectl get deploy -n "$NS" --no-headers 2>/dev/null | sort | awk '{printf "  %-46s %s\n", $1, $2}'

echo ""
echo "===== 2. 实际在跑的 StatefulSet ====="
kubectl get sts -n "$NS" --no-headers 2>/dev/null | sort | awk '{printf "  %-46s %s\n", $1, $2}'

echo ""
echo "===== 3. 所有 Pod 按组件归组统计 ====="
kubectl get pods -n "$NS" --no-headers 2>/dev/null | awk '{print $1}' \
  | sed -E 's/-[a-z0-9]+-[a-z0-9]+$//; s/-[0-9]+$//' \
  | sed -E 's/-[a-f0-9]{8,}-[a-z0-9]{5}$//' \
  | sort | uniq -c | sort -rn | awk '{printf "  %-46s %s\n", $2, $1}'

echo ""
echo "===== 4. 组件 Pod 健康总览 ====="
TOTAL=$(kubectl get pods -n "$NS" --no-headers 2>/dev/null | wc -l)
RUNNING=$(kubectl get pods -n "$NS" --no-headers 2>/dev/null | grep -c 'Running')
COMPLETED=$(kubectl get pods -n "$NS" --no-headers 2>/dev/null | grep -c 'Completed')
ABNORMAL=$(kubectl get pods -n "$NS" --no-headers 2>/dev/null | grep -vE 'Running|Completed' | wc -l)
echo "  总 Pod: $TOTAL   Running: $RUNNING   Completed: $COMPLETED   异常: $ABNORMAL"

echo ""
echo "===== 5. 非 Running/Completed 的 Pod（真异常）====="
kubectl get pods -n "$NS" --no-headers 2>/dev/null | grep -vE 'Running|Completed' | awk '{printf "  %-52s %-12s %s\n", $1, $3, $4}' | head -30

echo ""
echo "===== 6. 所有 Ingress 域名（看暴露了哪些服务）====="
kubectl get ingress -n "$NS" --no-headers 2>/dev/null | awk '{print $2, $3}' | sort -u | awk '{printf "  %-42s %s\n", $1, $2}'

echo ""
echo "===== 7. 官方 chart 里有哪些子 chart（对照缺什么）====="
ls -1 /root/bk-lite/charts 2>/dev/null | sed 's/^/  /' || \
ls -1 ./charts 2>/dev/null | sed 's/^/  /' || \
echo "  (chart 目录未找到，尝试其他路径)"
find / -maxdepth 6 -type d -name "bk-nodeman*" 2>/dev/null | head -3 | sed 's/^/  发现: /'
