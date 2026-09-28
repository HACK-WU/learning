#!/usr/bin/env bash
set -uo pipefail
{
echo "===== 1. migrate Job 当前状态 ====="
kubectl get job -n blueking --no-headers 2>/dev/null | grep -i 'monitor' | sed 's/^/  /'

echo ""
echo "===== 2. migrate Job 的 hook 策略（决定能否重建）====="
JOB=$(kubectl get job -n blueking --no-headers 2>/dev/null | grep -iE 'monitor.*migrate' | awk '{print $1}' | head -1)
echo "  JOB=$JOB"
if [ -n "$JOB" ]; then
  echo "  --- annotations ---"
  kubectl get job "$JOB" -n blueking -o jsonpath='{.metadata.annotations}' 2>/dev/null | tr ',' '\n' | sed 's/^/    /'
  echo "  --- labels ---"
  kubectl get job "$JOB" -n blueking -o jsonpath='{.metadata.labels}' 2>/dev/null | tr ',' '\n' | sed 's/^/    /'
  echo "  --- backoffLimit / completions ---"
  kubectl get job "$JOB" -n blueking -o jsonpath='  backoffLimit={.spec.backoffLimit}  completions={.spec.completions}  parallelism={.spec.parallelism}{"\n"}' 2>/dev/null
  echo "  --- ownerReferences (是否归属 helm) ---"
  kubectl get job "$JOB" -n blueking -o jsonpath='{.metadata.ownerReferences}' 2>/dev/null | sed 's/^/    /'
fi

echo ""
echo "===== 3. 该 Job 的 Pod 与重启次数 ====="
kubectl get pods -n blueking --no-headers 2>/dev/null | grep -iE 'monitor.*migrate' | sed 's/^/  /'

echo ""
echo "===== 4. chart 里该 job 的 hook 定义（解压看）====="
rm -rf /tmp/mchart && mkdir -p /tmp/mchart
helm pull blueking/bk-monitor --version 3.8.27 --destination /tmp/mchart --untar 2>&1 | head -2
grep -rlE 'hook.*post-install|migrate' /tmp/mchart/bk-monitor/templates/ 2>/dev/null | head -5 | sed 's/^/  /'
echo "  --- hook 注解内容 ---"
grep -rhoE 'helm.sh/hook[a-z-]*: *[^"]*' /tmp/mchart/bk-monitor/templates/ 2>/dev/null | sort -u | head -10 | sed 's/^/    /'
} > /root/survey-migrate.txt 2>&1
cat /root/survey-migrate.txt
