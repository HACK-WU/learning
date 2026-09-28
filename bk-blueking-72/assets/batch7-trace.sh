#!/usr/bin/env bash
NS=blueking

echo "=== 1. detect 的数据源在哪（看配置） ==="
pod=$(kubectl get pod -n $NS --no-headers 2>/dev/null | grep '^bk-monitor-alarm-detect-' | head -1 | awk '{print $1}')
kubectl exec -n $NS $pod -- env 2>/dev/null | grep -iE 'kafka|redis|influxdb|transfer|detect' | head -12 | sed 's/^/    /'

echo ""
echo "=== 2. 查 detect 用哪个 redis db（1000 是它的特征库） ==="
kubectl exec -n $NS $pod -- env 2>/dev/null | grep -iE 'redis' | head -6 | sed 's/^/    /'

echo ""
echo "=== 3. 看策略内容（12 个策略是什么） ==="
kubectl exec -n $NS $pod -- python -c "
import django,os
os.environ.setdefault('DJANGO_SETTINGS_MODULE','settings')
django.setup()
from bkmonitor.models import StrategyModel, ItemModel
for s in StrategyModel.objects.all()[:5]:
    print('  strategy id=%s name=%s enabled=%s' % (s.id, s.name, s.is_enabled))
print('  --- items ---')
for i in ItemModel.objects.all()[:5]:
    print('  item strategy_id=%s metric=%s' % (i.strategy_id, i.metric_id if hasattr(i,'metric_id') else '?'))
" 2>&1 | grep -vE 'Warning|warn|Cryptography|tongsuopy|Impacket|OpenTelemetry|PEP' | head -15
