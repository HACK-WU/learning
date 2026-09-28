#!/usr/bin/env bash
# 用途：对 4 类非200 逐个定性——判定真障碍 vs 可绕过
set -uo pipefail
R=hub.bktencent.com
get_token() {
  curl -s --max-time 20 "https://$R/service/token?service=harbor-registry&scope=repository:$1:pull" \
    | grep -oE '"token":"[^"]+"' | sed 's/"token":"//; s/"$//' | head -1
}
probe() {
  local t=$(get_token "$1")
  curl -s -o /dev/null -w "%{http_code}" --max-time 25 -H "Authorization: Bearer $t" \
    -H "Accept: application/vnd.docker.distribution.manifest.v2+json,application/vnd.docker.distribution.manifest.list.v2+json,application/vnd.oci.image.manifest.v1+json,application/vnd.oci.image.index.v1+json" \
    "https://$R/v2/$1/manifests/$2"
}

echo "===== A. influxdb 400 —— 真实名应为 library/influxdb ====="
echo "  library/influxdb:1.8.6-alpine -> $(probe library/influxdb 1.8.6-alpine)"

echo ""
echo "===== B. ingress-nginx —— 用 tag 而非 digest 再试 ====="
echo "  ingress-nginx/controller:v1.3.1 -> $(probe ingress-nginx/controller v1.3.1)"
echo "  ingress-nginx/kube-webhook-certgen:v1.3.0 -> $(probe ingress-nginx/kube-webhook-certgen v1.3.0)"

echo ""
echo "===== C. provisioner ====="
echo "  sig-storage/local-volume-provisioner:v2.4.0 -> $(probe sig-storage/local-volume-provisioner v2.4.0)"

echo ""
echo "===== D. bitnami 老 tag 缺失 —— 测同版本不同 revision 是否可替代 ====="
echo "  bitnami/kafka:3.4.0-debian-11-r15 -> $(probe bitnami/kafka 3.4.0-debian-11-r15)"
echo "  bitnami/mariadb:10.6.12-debian-11-r3 -> $(probe bitnami/mariadb 10.6.12-debian-11-r3)"
echo "  bitnami/mariadb:10.6.12-debian-11-r16 -> $(probe bitnami/mariadb 10.6.12-debian-11-r16)"
echo "  bitnami/redis:7.0.7-debian-11-r0 -> $(probe bitnami/redis 7.0.7-debian-11-r0)"

echo ""
echo "===== E. job 两个 404 自研镜像复核（可能是真缺失）====="
echo "  blueking/job-sync-bk-api-gateway:3.10.5-beta.3 -> $(probe blueking/job-sync-bk-api-gateway 3.10.5-beta.3)"
echo "  blueking/job-tools-k8s-startup-controller:3.10.5-beta.3 -> $(probe blueking/job-tools-k8s-startup-controller 3.10.5-beta.3)"

echo ""
echo "===== F. 对照：Docker Hub 上 bitnami/kafka 3.4.0 是否还在 ====="
T=$(curl -s --max-time 20 "https://auth.docker.io/token?service=registry.docker.io&scope=repository:bitnami/kafka:pull" | grep -oE '"token":"[^"]+"' | sed 's/"token":"//;s/"$//')
echo "  docker.io/bitnami/kafka:3.4.0-debian-11-r15 -> $(curl -s -o /dev/null -w '%{http_code}' --max-time 25 -H "Authorization: Bearer $T" -H "Accept: application/vnd.docker.distribution.manifest.v2+json" https://registry-1.docker.io/v2/bitnami/kafka/manifests/3.4.0-debian-11-r15)"
