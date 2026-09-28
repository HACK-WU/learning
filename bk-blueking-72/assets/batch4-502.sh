#!/usr/bin/env bash
NS=blueking

echo "=== 1. gateway 8080 为什么 502（看 upstream 配置） ==="
kubectl logs -n $NS deploy/bk-repo-bkrepo-gateway --tail=30 2>/dev/null | grep -iE '502|upstream|connect|refused|error' | tail -8
echo "  (空=日志无异常)"

echo ""
echo "=== 2. gateway 的 nginx conf 里 8080 代理到哪 ==="
kubectl exec -n $NS deploy/bk-repo-bkrepo-gateway -- sh -c \
  'ls /etc/nginx/conf.d/ 2>/dev/null; grep -rhoE "proxy_pass [^;]+" /etc/nginx/ 2>/dev/null | sort -u | head -12' 2>&1 | head -15

echo ""
echo "=== 3. 8081 是 UI（302 跳登录，符合预期）==="
kubectl run c1 --rm -i --restart=Never --image=curlimages/curl:8.5.0 -n $NS -- \
  curl -s -I --max-time 10 'http://bk-repo-bkrepo-gateway:8081/' 2>&1 | grep -iE 'HTTP/|location' | head -4

echo ""
echo "=== 4. 用 docker 官方协议验证 —— 拿 WWW-Authenticate 头 ==="
kubectl run c2 --rm -i --restart=Never --image=curlimages/curl:8.5.0 -n $NS -- \
  curl -s -D - -o /dev/null --max-time 10 'http://bk-repo-bkrepo-docker/v2/' 2>&1 | grep -iE 'HTTP/|www-authenticate|docker-distribution' | head -5

echo ""
echo "=== 5. generic 服务（generic 制品库） ==="
kubectl run c3 --rm -i --restart=Never --image=curlimages/curl:8.5.0 -n $NS -- \
  curl -s -w '\n  HTTP=%{http_code}\n' --max-time 10 'http://bk-repo-bkrepo-generic/' 2>&1 | head -6

echo ""
echo "=== 6. maven / npm / pypi 各自响应 ==="
for s in maven npm pypi; do
  kubectl run c$s --rm -i --restart=Never --image=curlimages/curl:8.5.0 -n $NS -- \
    curl -s -o /dev/null -w "    $s -> HTTP %{http_code}\n" --max-time 10 "http://bk-repo-bkrepo-$s/" 2>&1 | grep HTTP | head -1
done

echo ""
echo "=== 7. 清理 ==="
kubectl delete pod -n $NS c1 c2 c3 cmaven cnpm cpypi >/dev/null 2>&1
echo "  done"
