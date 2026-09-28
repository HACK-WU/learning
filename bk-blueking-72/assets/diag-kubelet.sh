#!/usr/bin/env bash
for c in k8s-c1-calico-worker k8s-c1-calico-worker2; do
  echo "########## $c ##########"
  echo "--- kubelet 进程 ---"
  docker exec $c bash -c 'ps aux | grep -c "[k]ubelet"' 2>&1 | sed 's/^/  /'
  echo "--- kubelet 服务状态 ---"
  docker exec $c bash -c 'service kubelet status 2>&1 | head -3' 2>&1 | sed 's/^/  /'
  echo "--- 容器内内存 ---"
  docker exec $c bash -c 'free -m | head -2' 2>&1 | sed 's/^/  /'
  echo "--- 容器内 PSI ---"
  docker exec $c bash -c 'cat /proc/pressure/memory 2>/dev/null | head -2' 2>&1 | sed 's/^/  /'
  echo "--- kubelet 日志尾部（真实报错） ---"
  docker exec $c bash -c 'journalctl -u kubelet --no-pager -n 8 2>/dev/null || tail -8 /var/log/kubelet.log 2>/dev/null' 2>&1 | tail -8 | sed 's/^/  /'
  echo "--- OOM 迹象 ---"
  docker exec $c bash -c 'dmesg 2>/dev/null | tail -30 | grep -iE "oom|killed" | tail -5' 2>&1 | sed 's/^/  /'
  echo ""
done
