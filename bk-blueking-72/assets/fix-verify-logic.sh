#!/usr/bin/env bash
set -uo pipefail
N=k8s-c1-calico-worker
I=hub.bktencent.com/beats/filebeat:7.7.1

echo "===== 1. ctr images list 的原始输出（看格式）====="
docker exec $N ctr -n k8s.io images list 2>/dev/null | grep filebeat | cat -A | head -3

echo ""
echo "===== 2. 用 awk '{print \$1}' 之后的值 ====="
docker exec $N ctr -n k8s.io images list 2>/dev/null | grep filebeat | awk '{print "["$1"]"}'

echo ""
echo "===== 3. 测试各种匹配方式 ====="
docker exec $N ctr -n k8s.io images list 2>/dev/null | awk '{print $1}' | grep -qx "$I" && echo "  grep -qx: 匹配" || echo "  grep -qx: 不匹配"
docker exec $N ctr -n k8s.io images list 2>/dev/null | grep -q "$I" && echo "  grep -q(整行): 匹配" || echo "  grep -q(整行): 不匹配"
docker exec $N ctr -n k8s.io images list -q 2>/dev/null | grep -qx "$I" && echo "  list -q + grep -qx: 匹配" || echo "  list -q + grep -qx: 不匹配"

echo ""
echo "===== 4. ctr images list -q 输出样例 ====="
docker exec $N ctr -n k8s.io images list -q 2>/dev/null | grep filebeat
