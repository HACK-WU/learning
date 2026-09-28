#!/usr/bin/env bash
NS=blueking

echo "=== 1. 找 ES 凭据 secret ==="
kubectl get secret -n $NS 2>/dev/null | grep -iE 'elastic' | awk '{print "  "$1}'

echo ""
echo "=== 2. 提取 elastic 用户密码 ==="
EP=$(kubectl get secret -n $NS bk-elastic-elasticsearch-es-elastic-user -o jsonpath='{.data.elastic}' 2>/dev/null | base64 -d 2>/dev/null)
if [ -z "$EP" ]; then
  # 试其他常见名字
  for s in elasticsearch-es-elastic-user bk-elastic-es-elastic-user elastic-credentials; do
    EP=$(kubectl get secret -n $NS $s -o jsonpath='{.data.elastic}' 2>/dev/null | base64 -d 2>/dev/null)
    [ -n "$EP" ] && echo "  从 $s 取到" && break
  done
fi
if [ -z "$EP" ]; then
  echo "  [未取到] 列出所有 secret 的 key 找 elastic 相关"
  kubectl get secret -n $NS -o json 2>/dev/null | python3 -c "
import json,sys,base64
d=json.load(sys.stdin)
for it in d.get('items',[]):
    n=it['metadata']['name']
    if 'elast' in n.lower():
        print('   ',n,'keys=',list(it.get('data',{}).keys()))
" 2>&1 | head -10
else
  echo "  密码长度: ${#EP}"
  echo ""
  echo "=== 3. 带认证查 ES 健康 ==="
  kubectl exec -n $NS bk-elastic-elasticsearch-coordinating-only-0 -- \
    curl -s -u "elastic:$EP" --max-time 10 'http://127.0.0.1:9200/_cluster/health?pretty' 2>&1 | head -14
  echo ""
  echo "=== 4. ES 索引列表 ==="
  kubectl exec -n $NS bk-elastic-elasticsearch-coordinating-only-0 -- \
    curl -s -u "elastic:$EP" --max-time 10 'http://127.0.0.1:9200/_cat/indices?v' 2>&1 | head -18
fi
