#!/usr/bin/env bash
NS=blueking

echo "=== 1. 真实 HTTP 调用 repository API（查项目列表） ==="
# bkrepo 的 repository 服务，列项目
kubectl run curltest --rm -i --restart=Never --image=curlimages/curl:8.5.0 -n $NS -- \
  curl -s -w '\n  HTTP=%{http_code}\n' --max-time 12 \
  'http://bk-repo-bkrepo-repository/api/repository/list/project?pageNumber=1&pageSize=5' 2>&1 | head -12

echo ""
echo "=== 2. 调 auth API ==="
kubectl run curltest2 --rm -i --restart=Never --image=curlimages/curl:8.5.0 -n $NS -- \
  curl -s -w '\n  HTTP=%{http_code}\n' --max-time 12 \
  'http://bk-repo-bkrepo-auth/api/user/list' 2>&1 | head -10

echo ""
echo "=== 3. 调 gateway 的 8081/8082 ==="
for p in 8080 8081 8082; do
  kubectl run curlp$p --rm -i --restart=Never --image=curlimages/curl:8.5.0 -n $NS -- \
    curl -s -o /dev/null -w "    port $p -> HTTP %{http_code}\n" --max-time 10 \
    "http://bk-repo-bkrepo-gateway:$p/" 2>&1 | grep -E 'HTTP|Error' | head -2
done

echo ""
echo "=== 4. docker registry v2 API（验证 docker 制品库真可用） ==="
kubectl run curldocker --rm -i --restart=Never --image=curlimages/curl:8.5.0 -n $NS -- \
  curl -s -w '\n  HTTP=%{http_code}\n' --max-time 12 \
  'http://bk-repo-bkrepo-docker/v2/' 2>&1 | head -8

echo ""
echo "=== 5. helm chart 仓库 index ==="
kubectl run curlhelm --rm -i --restart=Never --image=curlimages/curl:8.5.0 -n $NS -- \
  curl -s -o /dev/null -w "    helm -> HTTP %{http_code}\n" --max-time 10 \
  'http://bk-repo-bkrepo-helm/index.yaml' 2>&1 | grep -E 'HTTP|Error' | head -2

echo ""
echo "=== 6. 清理临时 pod ==="
kubectl delete pod -n $NS curltest curltest2 curlp8080 curlp8081 curlp8082 curldocker curlhelm >/dev/null 2>&1
echo "  done"
