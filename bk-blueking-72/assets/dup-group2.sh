#!/usr/bin/env bash
NS=blueking
echo "=== NOT-READY DEPLOYS (correct parse) ==="
kubectl get deploy -n $NS --no-headers 2>/dev/null | awk '{split($2,a,"/"); if(a[2]+0==0) print $1}' | sort > /tmp/dead.txt
echo "  count: $(wc -l < /tmp/dead.txt)"
cat /tmp/dead.txt | sed 's/^/    /'
echo ""
echo "=== REQUESTS of not-ready deploys ==="
TOT=0
for d in $(cat /tmp/dead.txt); do
  M=$(kubectl get deploy "$d" -n $NS -o jsonpath='{range .spec.template.spec.containers[*]}{.resources.requests.memory}{" "}{end}' 2>/dev/null)
  [ -n "$(echo $M)" ] && echo "    $d : $M"
done
