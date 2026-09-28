#!/usr/bin/env bash
NS=blueking
EP=$(kubectl get secret -n $NS bk-elastic-elasticsearch -o jsonpath='{.data.elasticsearch-password}' 2>/dev/null | base64 -d 2>/dev/null)
MARK="BATCH5-E2E-$(date +%s)"

echo "=== 1. logstash 端口与管道就绪 ==="
kubectl exec -n $NS bk-applog-bkapp-logstash-0 -- \
  curl -s --max-time 10 'http://127.0.0.1:9600/_node/pipelines?pretty' 2>&1 \
  | grep -E '"id"|"ephemeral_id"' | head -12
echo "  ---"
kubectl exec -n $NS bk-applog-bkapp-logstash-0 -- \
  curl -s -o /dev/null -w "    logstash API -> HTTP %{http_code}\n" --max-time 10 'http://127.0.0.1:9600/' 2>&1 | grep HTTP

echo ""
echo "=== 2. beats 输入端口是否监听（5044/5045/5046） ==="
kubectl exec -n $NS bk-applog-bkapp-logstash-0 -- \
  sh -c 'netstat -tlnp 2>/dev/null | grep -E "504[456]|9600" || ss -tln 2>/dev/null | grep -E "504[456]|9600"' 2>&1 | head -6

echo ""
echo "=== 3. 注入一条测试日志到 stdout ==="
echo "[$MARK] batch5 end-to-end verification log entry" >> /tmp/batch5-test.log 2>/dev/null
# 直接往容器 stdout 打标记（filebeat-stdout 采集容器日志）
kubectl exec -n $NS bk-applog-bkapp-logstash-0 -- \
  sh -c "echo '[$MARK] batch5 e2e test' > /proc/1/fd/1" 2>&1 | head -2
echo "  标记: $MARK"

echo ""
echo "=== 4. 等 60s 让采集链路走完 ==="
sleep 60

echo ""
echo "=== 5. ES 中搜这个标记 ==="
kubectl exec -n $NS bk-elastic-elasticsearch-coordinating-only-0 -- \
  curl -s -u "elastic:$EP" --max-time 15 \
  "http://127.0.0.1:9200/_search?q=$MARK&pretty" 2>&1 | grep -E '"total"|"value"|"_index"' | head -8

echo ""
echo "=== 6. ES 索引变化（看有无新增） ==="
kubectl exec -n $NS bk-elastic-elasticsearch-coordinating-only-0 -- \
  curl -s -u "elastic:$EP" --max-time 12 'http://127.0.0.1:9200/_cat/indices?v&s=index' 2>&1 | grep "$(date +%Y.%m.%d)" | head -8

echo ""
echo "=== 7. logstash 日志尾部（看有无 ERROR） ==="
kubectl logs -n $NS bk-applog-bkapp-logstash-0 --tail=30 2>/dev/null | grep -iE 'error|exception|warn' | head -5
echo "  (空=无异常)"
