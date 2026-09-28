#!/usr/bin/env bash
set -uo pipefail
NS=blueking

echo "===== 1. 当前还有几个 apigw 类 Pod 异常 ====="
kubectl get pods -n $NS --no-headers 2>/dev/null | grep -vE 'Running|Completed' | awk '{printf "  %-50s %-20s 重启%s\n", $1, $3, $4}'
echo "  --- 总计异常: $(kubectl get pods -n $NS --no-headers 2>/dev/null | grep -vE 'Running|Completed' | wc -l) ---"

echo ""
echo "===== 2. bk-apigateway-bkapi svc 详情 ====="
kubectl get svc bk-apigateway-bkapi -n $NS -o jsonpath='  ClusterIP={.spec.clusterIP}  ports={range .spec.ports[*]}{.port}{" "}{end}{"\n"}' 2>&1

echo ""
echo "===== 3. 是否有任何 ingress 指向 bkapi（全量搜）====="
kubectl get ingress -n $NS -o jsonpath='{range .items[*]}{.metadata.name}{" | "}{range .spec.rules[*]}{.host}{" "}{end}{"\n"}{end}' 2>/dev/null | sed 's/^/  /'

echo ""
echo "===== 4. 直连测试：bk-apigateway-bkapi:80 能否响应 sync API ====="
BK=$(kubectl get svc bk-apigateway-bkapi -n $NS -o jsonpath='{.spec.clusterIP}')
echo "  bkapi svc ClusterIP = $BK"
kubectl exec paas3-mig-probe -n $NS -- bash -c "curl -s -o /dev/null -w '    /api/bk-apigateway/prod/ HTTP %{http_code}\n' --max-time 8 http://$BK/api/bk-apigateway/prod/" 2>&1
kubectl exec paas3-mig-probe -n $NS -- bash -c "curl -s -o /dev/null -w '    root HTTP %{http_code}\n' --max-time 8 http://$BK/" 2>&1

echo ""
echo "===== 5. 对比：bk-apigateway-core-api 能否响应 ====="
CA=$(kubectl get svc bk-apigateway-core-api -n $NS -o jsonpath='{.spec.clusterIP}')
echo "  core-api ClusterIP = $CA"
kubectl exec paas3-mig-probe -n $NS -- bash -c "curl -s -o /dev/null -w '    /api/bk-apigateway/prod/ HTTP %{http_code}\n' --max-time 8 http://$CA/api/bk-apigateway/prod/" 2>&1

echo ""
echo "===== 6. apigateway 主服务 6006 端口 ====="
AG=$(kubectl get svc bk-apigateway-apigateway -n $NS -o jsonpath='{.spec.clusterIP}')
kubectl exec paas3-mig-probe -n $NS -- bash -c "curl -s -o /dev/null -w '    6006 root HTTP %{http_code}\n' --max-time 8 http://$AG:6006/" 2>&1

echo ""
echo "===== 7. 关键：原生部署里 bkapi 域名该指向谁？看 apigateway 的 values/配置 ====="
kubectl get cm -n $NS -o name 2>/dev/null | grep -i 'apigateway' | head -8 | sed 's/^/  /'
echo "  --- 找 BK_API_URL / BK_APIGW 相关配置 ---"
kubectl get cm bk-apigateway-apigateway -n $NS -o yaml 2>/dev/null | grep -iE 'BK_API|api_url|bkapi|gateway_url' | head -8 | sed 's/^/    /'

echo ""
echo "===== 8. gse apigw sync 的完整报错头（确认是否只有 bkapi 404）====="
kubectl logs bk-gse-apigw-sync-1-kjcg8 -n $NS --tail=3 2>&1 | head -3 | cut -c1-160 | sed 's/^/    /'
