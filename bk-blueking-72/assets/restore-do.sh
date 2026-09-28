#!/usr/bin/env bash
NS=blueking

echo "=== STEP 1: 还原 kafka 探针（原值 failure=3 / init=10） ==="
kubectl patch sts -n $NS bk-kafka --type='json' -p='[
  {"op":"replace","path":"/spec/template/spec/containers/0/livenessProbe/initialDelaySeconds","value":10},
  {"op":"replace","path":"/spec/template/spec/containers/0/livenessProbe/failureThreshold","value":3}
]' >/dev/null 2>&1 && echo "  [还原] kafka liveness -> init=10 failure=3"

echo ""
echo "=== STEP 2: 还原 bkrepo 11 个探针（原值 init=120，gateway 是 60） ==="
for d in auth docker generic helm job maven npm opdata pypi replication repository; do
  kubectl patch deploy -n $NS bk-repo-bkrepo-$d --type='json' -p='[
    {"op":"replace","path":"/spec/template/spec/containers/0/livenessProbe/initialDelaySeconds","value":120}
  ]' >/dev/null 2>&1
done
echo "  11 个（除 generic）liveness init -> 120"
kubectl patch deploy -n $NS bk-repo-bkrepo-gateway --type='json' -p='[
  {"op":"replace","path":"/spec/template/spec/containers/0/livenessProbe/initialDelaySeconds","value":60}
]' >/dev/null 2>&1 && echo "  gateway liveness init -> 60（原值）"

echo ""
echo "=== STEP 3: 校验还原结果 ==="
echo "  --- kafka ---"
kubectl get sts -n $NS bk-kafka -o jsonpath='{.spec.template.spec.containers[0].livenessProbe}' 2>/dev/null | head -c 160
echo ""
echo "  --- bkrepo（抽样 3 个 + gateway） ---"
for d in auth opdata gateway; do
  v=$(kubectl get deploy -n $NS bk-repo-bkrepo-$d -o jsonpath='{.spec.template.spec.containers[0].livenessProbe.initialDelaySeconds}' 2>/dev/null)
  printf "    %-12s liveness_init=%s\n" "$d" "$v"
done

echo ""
echo "=== STEP 4: 等 120s 观察 kafka 是否被杀（关键验证） ==="
sleep 120
kubectl get pods -n $NS --no-headers 2>/dev/null | grep -E '^bk-kafka-0' | awk '{print "    "$1" "$3" restarts="$4}'

echo ""
echo "=== STEP 5: kafka 若被重启，看原因 ==="
kubectl get events -n $NS --sort-by='.lastTimestamp' 2>/dev/null | grep -i kafka | tail -3

echo ""
echo "=== STEP 6: 集群与内存 ==="
kubectl get pods -n $NS --no-headers 2>/dev/null | awk '{print $3}' | sort | uniq -c | sort -rn | head -4
free -g | sed -n '2p' | awk '{printf "    used=%sG avail=%sG\n",$3,$7}'
