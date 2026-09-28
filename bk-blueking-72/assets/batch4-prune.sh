#!/usr/bin/env bash
NS=blueking
echo "=== STEP 1: 裁前留证 —— bk-repo 全量状态 ==="
kubectl get deploy -n $NS --no-headers 2>/dev/null | grep '^bk-repo' > /tmp/repo-before.txt
echo "  组件数: $(wc -l < /tmp/repo-before.txt)  全部 1/1: $(grep -c '1/1' /tmp/repo-before.txt)"
cat /tmp/repo-before.txt | awk '{printf "    %-44s %s\n",$1,$2}'

echo ""
echo "=== STEP 2: 裁前留证 —— 决定性证据（docker v2 协议） ==="
kubectl run cev --rm -i --restart=Never --image=curlimages/curl:8.5.0 -n $NS -- \
  curl -s -D - -o /dev/null --max-time 10 'http://bk-repo-bkrepo-docker/v2/' 2>&1 \
  | grep -iE 'HTTP/|Docker-Distribution|WWW-Authenticate' | sed 's/^/    /'

echo ""
echo "=== STEP 3: 裁前内存 ==="
free -g | sed -n '2p' | awk '{printf "    used=%sG avail=%sG\n",$3,$7}'

echo ""
echo "=== STEP 4: 裁掉 bk-repo 12 个 ==="
for d in $(awk '{print $1}' /tmp/repo-before.txt); do
  kubectl scale deploy -n $NS $d --replicas=0 >/dev/null 2>&1
done
echo "  已 scale 0: $(wc -l < /tmp/repo-before.txt) 个"

echo ""
echo "=== STEP 5: 等 90s 回收 ==="
sleep 90
free -g | sed -n '2p' | awk '{printf "    裁后 used=%sG avail=%sG\n",$3,$7}'

echo ""
echo "=== STEP 6: 集群整体健康（裁后不应有影响） ==="
kubectl get pods -n $NS --no-headers 2>/dev/null | awk '{print $3}' | sort | uniq -c | sort -rn | head -5

echo ""
echo "=== STEP 7: 核心页面复查 ==="
for d in paas.example.com bkpaas.paas.example.com bkiam.paas.example.com bkuser.paas.example.com apigw.paas.example.com bkmonitor.paas.example.com; do
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "http://$d/" 2>/dev/null)
  printf "    %-30s %s\n" "$d" "$code"
done
