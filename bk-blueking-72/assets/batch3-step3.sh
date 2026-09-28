#!/usr/bin/env bash
NS=blueking
echo "=== STEP 1: 启动告警链路（26 个，分批每次 6 个，避免内存尖峰） ==="
ALL=$(kubectl get deploy -n $NS --no-headers 2>/dev/null | awk '{print $1}' | grep '^bk-monitor-alarm-' | sort)
echo "  待启动: $(echo $ALL | wc -w) 个"

n=0
for d in $ALL; do
  cur=$(kubectl get deploy -n $NS $d -o jsonpath='{.spec.replicas}' 2>/dev/null)
  if [ "$cur" == "0" ]; then
    kubectl scale deploy -n $NS $d --replicas=1 >/dev/null 2>&1
    n=$((n+1))
    printf "  [%2d] %s\n" "$n" "$d"
    # 每 6 个等 40s
    if [ $((n % 6)) -eq 0 ]; then
      echo "    --- 已起 $n 个，等 40s 让内存稳定 ---"
      sleep 40
      free -g | sed -n '2p' | awk '{printf "    内存 used=%sG avail=%sG\n",$3,$7}'
    fi
  fi
done

echo ""
echo "=== STEP 2: 等 120s 全部就绪 ==="
sleep 120

echo ""
echo "=== STEP 3: 告警链路副本状态 ==="
kubectl get deploy -n $NS --no-headers 2>/dev/null | grep '^bk-monitor-alarm-' | awk '{printf "  %-46s %s\n",$1,$2}'

echo ""
echo "=== STEP 4: 未就绪的 ==="
kubectl get deploy -n $NS --no-headers 2>/dev/null | grep '^bk-monitor-alarm-' | awk '$2!=$3 || $2 ~ /^0\// {print "  [未就绪] "$1" "$2}'

echo ""
echo "=== STEP 5: 内存 ==="
free -g | sed -n '1,2p'
