#!/usr/bin/env bash
# 深挖：etcd target up=0 的原因（证书？端口？Service 选择器？）
# 安全声明：全部只读（查询 Prometheus API / 读配置 / 容器内读端口），不改任何资源
set -uo pipefail

hr() { printf '\n========== %s ==========\n' "$*"; }

PROM_POD=$(kubectl -n monitoring get pod -o name | grep 'prometheus-kps' | head -1 | sed 's|^pod/||')
q() {
  kubectl -n monitoring exec "$PROM_POD" -c prometheus -- sh -c \
    "wget -qO- 'http://localhost:9090/api/v1/query?query=$1' 2>/dev/null" | head -c 1200
  echo
}

hr 'A. 复现 up=0（确认不是偶发）'
q 'up{job="kube-etcd"}'

hr 'B. 抓取错误信息（scrape 失败的具体原因）'
q 'scrape_duration_seconds{job="kube-etcd"}'
echo
echo '--- 最近一次抓取是否报错：看 up 的 sample 与 scrape_series_added ---'
q 'scrape_samples_scraped{job="kube-etcd"}'

hr 'C. 对照：其他 job 的 up 值（证明只有 etcd 挂）'
q 'up{job="apiserver"}'
echo
q 'up{job="kube-state-metrics"}'

hr 'D. ServiceMonitor 的端口与 scheme 配置（http-metrics / https）'
kubectl -n monitoring get servicemonitor kps-kube-prometheus-stack-kube-etcd -o jsonpath='{.spec}' 2>/dev/null \
  | tr ',' '\n' | head -40

hr 'E. etcd Service 的 endpoint 与端口暴露'
kubectl -n kube-system get svc -l 'app.kubernetes.io/name=etcd' 2>/dev/null
echo '--- 若无 svc，看 ServiceMonitor 的 selector 匹配到谁 ---'
kubectl -n kube-system get pod etcd-k8s-c1-calico-control-plane -o jsonpath='{.metadata.labels}' 2>/dev/null
echo
echo '--- etcd Pod 暴露的端口 ---'
kubectl -n kube-system get pod etcd-k8s-c1-calico-control-plane -o jsonpath='{range .spec.containers[0].ports[*]}{.name}={.containerPort} {end}' 2>/dev/null
echo

hr 'F. 端到端验证：从 prometheus 容器内直连 etcd 指标端口（2381/http）'
kubectl -n monitoring exec "$PROM_POD" -c prometheus -- sh -c \
  'wget -qO- --timeout=5 http://172.27.0.6:2381/metrics 2>&1 | head -c 300' 2>&1
echo
echo '>>> 若能取到内容 = 网络通、指标在；取不到 = 被网络策略/端口拦'

hr 'G. 校准 NetworkPolicy：是不是 Calico 策略拦了跨命名空间抓取'
kubectl get networkpolicy -A 2>&1 | head

hr '深挖结束'
