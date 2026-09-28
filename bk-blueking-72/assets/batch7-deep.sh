#!/usr/bin/env bash
NS=blueking

echo "=== 1. 策略表有多少条（为什么 published 0/12） ==="
pod=$(kubectl get pod -n $NS --no-headers 2>/dev/null | grep '^bk-monitor-alarm-nodata-' | head -1 | awk '{print $1}')
kubectl exec -n $NS $pod -- python -c "
import django,os
os.environ.setdefault('DJANGO_SETTINGS_MODULE','settings')
django.setup()
from bkmonitor.models import StrategyModel
from bkmonitor.models import ItemModel
print('  Strategy 总数:', StrategyModel.objects.count())
print('  Item 总数    :', ItemModel.objects.count())
" 2>&1 | grep -E '总数|Error|error' | head -5

echo ""
echo "=== 2. alert 连的是 kafka，看它消费的 topic 有没有数据 ==="
kubectl exec -n $NS bk-kafka-0 -- kafka-consumer-groups.sh --bootstrap-server localhost:9092 --list 2>/dev/null | grep -i alert | head -5 | sed 's/^/    /'
echo "  (空=alert 消费组还没建，因为它没收到数据)"

echo ""
echo "=== 3. rabbitmq 通不通（worker 连的是它） ==="
kubectl get pods -n $NS --no-headers 2>/dev/null | grep -i rabbit | awk '{print "    "$1" "$3}'

echo ""
echo "=== 4. 关键：造一条真告警数据走完全程（唯一标记法） ==="
# 看 detect 从哪读数据
kubectl exec -n $NS $pod -- python -c "
import os
print('  BACKEND:', os.environ.get('BKAPP_ALARM_BACKEND') or 'n/a')
print('  KAFKA  :', os.environ.get('BK_KAFKA_HOST') or 'n/a')
" 2>&1 | head -3

echo ""
echo "=== 5. 查 detect 消费的 kafka topic 有无数据 ==="
kubectl exec -n $NS bk-kafka-0 -- kafka-topics.sh --bootstrap-server localhost:9092 --list 2>/dev/null | grep -iE 'alert|alarm|detect' | head -5 | sed 's/^/    /'

echo ""
echo "=== 6. 看 monitor-api 能否查到策略（业务层验证） ==="
kubectl run cm7 --rm -i --restart=Never --image=curlimages/curl:8.5.0 -n $NS -- \
  curl -s --max-time 12 'http://bk-monitor-api/api/v3/query/' -o /dev/null -w '    monitor-api HTTP=%{http_code}\n' 2>&1 | grep HTTP
