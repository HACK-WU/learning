#!/usr/bin/env bash
set -uo pipefail
NS=blueking

echo "===== 1. 全局异常 Pod ====="
kubectl get pods -n $NS --no-headers 2>/dev/null | grep -vE 'Running|Completed' | awk '{printf "  %-52s %-20s 重启%s\n", $1, $3, $4}'
echo "  --- 总 Pod: $(kubectl get pods -n $NS --no-headers 2>/dev/null | wc -l)  异常: $(kubectl get pods -n $NS --no-headers 2>/dev/null | grep -vE 'Running|Completed' | wc -l) ---"

echo ""
echo "===== 2. 还缺 ingress 的域名？检查所有 paas.example.com 子域 ====="
echo "  已有 ingress host:"
kubectl get ingress -n $NS -o jsonpath='{range .items[*]}{range .spec.rules[*]}{.host}{"\n"}{end}{end}' 2>/dev/null | sort -u | sed 's/^/    /'

echo ""
echo "  --- apigw 需要的域名（各组件配置里的 BK_API_URL）---"
for cm in bk-cmdb-general-envs bk-gse-general-envs bkiam-saas-general-envs; do
  kubectl get cm $cm -n $NS -o yaml 2>/dev/null | grep -oE 'https?://[a-z0-9.-]*example[a-z.]*' | sort -u | sed "s/^/    [$cm] /"
done

echo ""
echo "===== 3. 剩余 apigw sync 类 Job 状态 ====="
kubectl get jobs -n $NS --no-headers 2>/dev/null | grep -iE 'apigw|sync' | awk '{printf "  %-50s %-12s\n", $1, $2}'

echo ""
echo "===== 4. paas3 是否还卡 Init ====="
kubectl get pods -n $NS --no-headers 2>/dev/null | grep bkpaas3 | grep -v Running | awk '{printf "  %-52s %-16s 重启%s\n", $1, $3, $4}'
echo "  卡 Init 数: $(kubectl get pods -n $NS --no-headers 2>/dev/null | grep -c 'Init:')"

echo ""
echo "===== 5. bk-cmdb 相关 ====="
kubectl get pods -n $NS --no-headers 2>/dev/null | grep 'bk-cmdb' | grep -v Running | awk '{printf "  %-52s %-16s 重启%s\n", $1, $3, $4}'

echo ""
echo "===== 6. 新出现的 CrashLoop（如果有）抓报错 ====="
for p in $(kubectl get pods -n $NS --no-headers 2>/dev/null | grep 'CrashLoop' | awk '{print $1}' | head -3); do
  echo "  --- $p ---"
  kubectl logs $p -n $NS --tail=8 2>&1 | grep -viE 'InsecureKey|Deprecat' | tail -6 | sed 's/^/    /'
done
