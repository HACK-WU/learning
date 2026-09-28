#!/usr/bin/env bash
set -uo pipefail

{
echo "===== 1. migrate Job 实际用的 app_code（从环境变量确认）====="
kubectl get job bk-monitor-migrate-1 -n blueking -o jsonpath='{range .spec.template.spec.containers[*].env[*]}{.name}={.value}{"\n"}{end}' 2>/dev/null | grep -iE 'APP_CODE|APP_SECRET' | sed 's/^/  /'

echo ""
echo "===== 2. 从 helm release values 确认 appCode ====="
helm get values bk-monitor -n blueking 2>/dev/null | grep -iE 'appCode|app_code|appSecret' | head -10 | sed 's/^/  /'

echo ""
echo "===== 3. chart 默认 appCode（values.yaml 里）====="
helm show values blueking/bk-monitor --version 3.8.27 2>/dev/null | grep -iE 'appCode|appSecret' -A2 | head -20 | sed 's/^/  /'

echo ""
echo "===== 4. 官方 values 里怎么配的 ====="
grep -iE 'appCode|appSecret|app_code' /root/bk72/install/blueking/environments/default/bkmonitor-values.yaml.gotmpl 2>/dev/null | head -15 | sed 's/^/  /'

echo ""
echo "===== 5. 对比 unify-query 用的 app_code（它授权成功了）====="
helm get values bk-monitor -n blueking 2>/dev/null | grep -iE 'unifyQuery' -A10 | grep -iE 'appCode|app_code' | head -5 | sed 's/^/  /'

echo ""
echo "===== 6. 关键：migrate 报错发生在哪个 app_code 下 ====="
kubectl logs -n blueking bk-monitor-migrate-1-2htvr -c on-migrate 2>/dev/null | grep -iE 'app_code|bk_app_code|X-Bk-App' | head -10 | sed 's/^/  /'
} > /root/verify-appcode.txt 2>&1
cat /root/verify-appcode.txt
