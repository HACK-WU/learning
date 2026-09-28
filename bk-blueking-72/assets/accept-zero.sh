#!/usr/bin/env bash
NS=blueking
echo "=== 47 个未起 deploy 的构成（按前缀归类） ==="
kubectl get deploy -n $NS --no-headers 2>/dev/null | awk '$2=="0/0"{print $1}' > /tmp/zero.txt
echo "    总数: $(wc -l < /tmp/zero.txt)"
echo ""
sed 's/-[a-z]*$//' /tmp/zero.txt | sort | uniq -c | sort -rn | head -20 | awk '{printf "    %-40s %s\n",$2,$1}'

echo ""
echo "=== 按批次归类（人工映射） ==="
for p in "bk-repo-:第4批制品库" "bk-nodeman-backend-:第6批节点管理" "bk-monitor-alarm-:第7批告警链路" \
         "bk-applog-bkapp-logstash:第5批logstash" "bkiam-saas-beat:第8批" "bkiam-saas-worker:第8批" \
         "bk-apigateway-dashboard-beat:第8批" "bk-apigateway-dashboard-celery:第8批"; do
  k="${p%%:*}"; n=$(grep -c "^$k" /tmp/zero.txt)
  printf "    %-32s %-18s %s\n" "$k" "${p##*:}" "$n"
done

echo ""
echo "=== 未归类（不属于上述任何批次）==="
grep -vE 'bk-repo-|bk-nodeman-backend-|bk-monitor-alarm-|bk-applog-bkapp-logstash|bkiam-saas-beat|bkiam-saas-worker|bk-apigateway-dashboard-beat|bk-apigateway-dashboard-celery' /tmp/zero.txt | sed 's/^/    /'

echo ""
echo "=== 那 4 个第8批组件确认已缩回 0 ==="
kubectl get deploy -n $NS bkiam-saas-beat bkiam-saas-worker bk-apigateway-dashboard-beat bk-apigateway-dashboard-celery --no-headers 2>/dev/null | awk '{print "    "$1" "$2}'
