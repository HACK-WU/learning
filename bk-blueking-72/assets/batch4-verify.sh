#!/usr/bin/env bash
NS=blueking
GW=bk-repo-bkrepo-gateway

echo "=== 1. gateway 服务端口 ==="
kubectl get svc -n $NS $GW --no-headers 2>/dev/null | awk '{print "  "$1" "$5}'

echo ""
echo "=== 2. 通过 ingress 域名实测 ==="
for d in bkrepo.paas.example.com docker.paas.example.com helm.paas.example.com static.bkrepo.example.com svc-bkrepo.paas.example.com; do
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "http://$d/" 2>/dev/null)
  printf "  %-34s %s\n" "$d" "$code"
done

echo ""
echo "=== 3. gateway 容器内自测 ==="
kubectl exec -n $NS deploy/$GW -- sh -c 'wget -qO- --timeout=8 http://127.0.0.1:8080/ 2>&1 | head -3 || echo "  (wget 无输出/无工具)"' 2>&1 | head -4

echo ""
echo "=== 4. bkrepo 各服务 Pod 日志尾部（看有无 ERROR） ==="
for d in bk-repo-bkrepo-auth bk-repo-bkrepo-repository bk-repo-bkrepo-generic; do
  err=$(kubectl logs -n $NS deploy/$d --tail=40 2>/dev/null | grep -ci 'error' )
  printf "  %-34s 近40行 ERROR 数: %s\n" "$d" "$err"
done

echo ""
echo "=== 5. auth 服务健康（repository 依赖 auth） ==="
kubectl exec -n $NS deploy/bk-repo-bkrepo-repository -- sh -c \
  'wget -qO- --timeout=8 http://bk-repo-bkrepo-auth:80/ 2>&1 | head -2; echo "  exit=$?"' 2>&1 | head -3

echo ""
echo "=== 6. 真实创建仓库（bkrepo API） ==="
# bkrepo 创建 generic 仓库
kubectl exec -n $NS deploy/bk-repo-bkrepo-gateway -- sh -c \
  'wget -qO- --timeout=10 --post-data="" "http://127.0.0.1:8080/repository/api/repo/create" 2>&1 | head -3; echo "  exit=$?"' 2>&1 | head -4

echo ""
echo "=== 7. 内存 ==="
free -g | sed -n '2p' | awk '{printf "    used=%sG avail=%sG\n",$3,$7}'
