#!/usr/bin/env bash
NS=blueking
echo "=== STEP 1: 裁掉非本批组件（bk-repo 第4批 / applog 第5批）腾内存 ==="

# bk-repo 全系列
for d in $(kubectl get deploy -n $NS --no-headers 2>/dev/null | awk '{print $1}' | grep -E '^bk-repo-bkrepo-'); do
  cur=$(kubectl get deploy -n $NS $d -o jsonpath='{.spec.replicas}' 2>/dev/null)
  if [ "$cur" != "0" ]; then
    kubectl scale deploy -n $NS $d --replicas=0 >/dev/null 2>&1 && echo "  [裁] $d (was $cur)"
  fi
done

# applog（sts + daemonset 也要处理）
kubectl scale deploy -n $NS bk-applog-bkapp-logstash --replicas=0 >/dev/null 2>&1 && echo "  [裁] bk-applog-bkapp-logstash"
kubectl patch sts -n $NS bk-applog-bkapp-logstash -p '{"spec":{"replicas":0}}' >/dev/null 2>&1 && echo "  [裁] sts bk-applog-bkapp-logstash"

echo ""
echo "=== STEP 2: 放宽 kafka 探针（40s → 180s）==="
kubectl patch sts -n $NS bk-kafka --type='json' -p='[
  {"op":"replace","path":"/spec/template/spec/containers/0/livenessProbe/initialDelaySeconds","value":180},
  {"op":"replace","path":"/spec/template/spec/containers/0/livenessProbe/failureThreshold","value":12},
  {"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/initialDelaySeconds","value":60},
  {"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/failureThreshold","value":30}
]' 2>&1 | sed 's/^/  /'

echo ""
echo "=== STEP 3: 删掉 kafka pod 让它用新探针重建 ==="
kubectl delete pod -n $NS bk-kafka-0 --grace-period=30 2>&1 | sed 's/^/  /'

echo ""
echo "=== STEP 4: 等 60s 看内存回收 ==="
sleep 60
free -g | sed -n '1,2p' | sed 's/^/  /'
