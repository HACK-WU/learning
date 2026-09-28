#!/usr/bin/env bash
NS=blueking

echo "=== 1. 从 helm chart 找 kafka探针原值 ==="
CH=$(helm list -n $NS -o json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
for r in d:
    if 'kafka' in r['name']: print(r['chart'])
" 2>/dev/null)
echo "  chart: $CH"
# 找 chart 解压目录
find /root/.cache/helm /home -type d -name 'kafka*' 2>/dev/null | head -5
helm show values $(echo $CH | sed 's/-[0-9.]*$//') --repo 2>/dev/null | head -3

echo ""
echo "=== 2. 直接查 chart 包里的 values.yaml ==="
helm pull $(echo $CH | sed 's/-[0-9.]*$//') --untar --untardir /tmp/chartk 2>/dev/null >/dev/null 2>&1
ls /tmp/chartk 2>/dev/null
grep -rn -A6 -iE 'livenessProbe|readinessProbe' /tmp/chartk/*/values.yaml 2>/dev/null | head -25

echo ""
echo "=== 3. kafka Pod 上有没有注解记录原值 ==="
kubectl get sts -n $NS bk-kafka -o jsonpath='{.metadata.annotations}' 2>/dev/null | head -c 500
echo ""

echo ""
echo "=== 4. 查之前的留证脚本/报告里是否记了原值 ==="
grep -rn -E 'initialDelaySeconds|initial.*=|原值|180' /mnt/d/projects/learning/bk-blueking-72/*.md 2>/dev/null | head -12

echo ""
echo "=== 5. bkrepo chart 探针原值 ==="
helm pull blueking/bk-repo --untar --untardir /tmp/chartr 2>/dev/null >/dev/null 2>&1
grep -rn -A6 -iE 'livenessProbe|readinessProbe' /tmp/chartr/*/values.yaml 2>/dev/null | head -20
