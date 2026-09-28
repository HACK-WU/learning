#!/usr/bin/env bash
NS=blueking
echo "=== 1. 所有副本=0 的 deploy（剩余未验证的） ==="
kubectl get deploy -n $NS --no-headers 2>/dev/null | awk '$2=="0/0"{print "  deploy  "$1}'

echo ""
echo "=== 2. 所有副本=0 的 sts ==="
kubectl get sts -n $NS --no-headers 2>/dev/null | awk '$2=="0/0"{print "  sts     "$1}'

echo ""
echo "=== 3. 所有副本=0 的 ds ==="
kubectl get ds -n $NS --no-headers 2>/dev/null | awk '{print "  ds      "$1" "$2}'

echo ""
echo "=== 4. logstash 详情（sts） ==="
kubectl get sts -n $NS bk-applog-bkapp-logstash -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}' 2>/dev/null
echo "  request mem: $(kubectl get sts -n $NS bk-applog-bkapp-logstash -o jsonpath='{.spec.template.spec.containers[0].resources.requests.memory}' 2>/dev/null)"
echo "  limit  mem:  $(kubectl get sts -n $NS bk-applog-bkapp-logstash -o jsonpath='{.spec.template.spec.containers[0].resources.limits.memory}' 2>/dev/null)"
echo "  liveness:    $(kubectl get sts -n $NS bk-applog-bkapp-logstash -o jsonpath='{.spec.template.spec.containers[0].livenessProbe}' 2>/dev/null | head -c 200)"

echo ""
echo "=== 5. ES 健康（日志要写 ES） ==="
kubectl run ces --rm -i --restart=Never --image=curlimages/curl:8.5.0 -n $NS -- \
  curl -s --max-time 10 'http://bk-elastic-elasticsearch-coordinating-only:9200/_cluster/health?pretty' 2>&1 | head -12

echo ""
echo "=== 6. bk-log 相关 secret/configmap 是否存在 ==="
kubectl get cm -n $NS 2>/dev/null | grep -iE 'log' | awk '{print "  cm   "$1}'
kubectl get secret -n $NS 2>/dev/null | grep -iE 'log' | awk '{print "  sec  "$1}'
