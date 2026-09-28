#!/usr/bin/env bash
set -uo pipefail

echo "===== 1. GSE 相关 Pod 状态 ====="
kubectl get pods -n blueking --no-headers 2>/dev/null | grep -iE 'gse' | head -20 | sed 's/^/  /'

echo ""
echo "===== 2. 监控里配置的 GSE 地址/凭据 ====="
kubectl get cm -n blueking -o name 2>/dev/null | grep -i monitor | head -20 | sed 's/^/  /'
echo "  --- bk-monitor-api 环境变量中的 GSE ---"
kubectl get deploy bk-monitor-api -n blueking -o jsonpath='{range .spec.template.spec.containers[0].env[*]}{.name}={.value}{"\n"}{end}' 2>/dev/null | grep -iE 'GSE|BKAPP_' | head -20 | sed 's/^/  /'

echo ""
echo "===== 3. 全局 GSE 配置（app_secret / 地址）====="
grep -iE 'gse' /root/bk72/install/blueking/environments/default/values.yaml 2>/dev/null | head -15 | sed 's/^/  /'
echo "  --- address.yaml.gotmpl 中的 gse ---"
grep -iE 'gse' /root/bk72/install/blueking/address.yaml.gotmpl 2>/dev/null | head -15 | sed 's/^/  /'

echo ""
echo "===== 4. apigw 凭据（403 常见于 app_code/secret 不对）====="
grep -iE 'app_code|app_secret|bk_app' /root/bk72/install/blueking/environments/default/app_secret.yaml 2>/dev/null | head -10 | sed 's/^/  /'

echo ""
echo "===== 5. 监控的 gse api 配置来源 ====="
grep -rnE 'gse' /root/bk72/install/blueking/environments/default/bkmonitor-values.yaml.gotmpl 2>/dev/null | head -15 | sed 's/^/  /'
