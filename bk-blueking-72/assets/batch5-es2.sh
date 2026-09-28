#!/usr/bin/env bash
NS=blueking
EP=$(kubectl get secret -n $NS bk-elastic-elasticsearch -o jsonpath='{.data.elasticsearch-password}' 2>/dev/null | base64 -d 2>/dev/null)
echo "  密码长度: ${#EP}"
echo ""

echo "=== 1. ES 集群健康 ==="
kubectl exec -n $NS bk-elastic-elasticsearch-coordinating-only-0 -- \
  curl -s -u "elastic:$EP" --max-time 12 'http://127.0.0.1:9200/_cluster/health?pretty' 2>&1 | head -16

echo ""
echo "=== 2. ES 索引列表 ==="
kubectl exec -n $NS bk-elastic-elasticsearch-coordinating-only-0 -- \
  curl -s -u "elastic:$EP" --max-time 12 'http://127.0.0.1:9200/_cat/indices?v' 2>&1 | head -20

echo ""
echo "=== 3. logstash 配置里 ES 地址与凭据来源 ==="
kubectl get cm -n $NS bk-applog-bkapp-logstash-config -o jsonpath='{.data}' 2>/dev/null | head -c 700
echo ""
echo "  --- pipeline ---"
kubectl get cm -n $NS bk-applog-bkapp-logstash-pipeline -o jsonpath='{.data}' 2>/dev/null | head -c 900
echo ""
