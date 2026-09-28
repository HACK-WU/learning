#!/usr/bin/env bash
# 用途：判定 401 性质——Harbor 未托管（可绕上游）vs 需授权（真障碍）
set -uo pipefail
R=hub.bktencent.com
echo "===== 1. 401 时的响应体（Harbor 未托管 vs 权限不足，措辞不同）====="
for repo in ingress-nginx/controller sig-storage/local-volume-provisioner; do
  T=$(curl -s --max-time 20 "https://$R/service/token?service=harbor-registry&scope=repository:$repo:pull" | grep -oE '"token":"[^"]+"' | sed 's/"token":"//;s/"$//' | head -1)
  echo "--- $repo ---"
  curl -s --max-time 20 -H "Authorization: Bearer $T" "https://$R/v2/$repo/manifests/v1.3.1" | head -c 250
  echo ""
done

echo ""
echo "===== 2. 这些是 K8s 上游镜像，测官方上游源是否可达（绕过方案）====="
echo "registry.k8s.io/ingress-nginx/controller:v1.3.1 -> $(curl -s -o /dev/null -w '%{http_code}' --max-time 25 https://registry.k8s.io/v2/ingress-nginx/controller/manifests/v1.3.1)"
echo "k8s.gcr.io(registry.k8s.io)/sig-storage/local-volume-provisioner:v2.4.0 -> $(curl -s -o /dev/null -w '%{http_code}' --max-time 25 https://registry.k8s.io/v2/sig-storage/local-volume-provisioner/manifests/v2.4.0)"

echo ""
echo "===== 3. 测国内可达的 K8s 镜像加速源 ====="
for reg in registry.aliyuncs.com registry.cn-hangzhou.aliyuncs.com; do
  echo "$reg/google_containers/nginx-ingress-controller:v1.3.1 -> $(curl -s -o /dev/null -w '%{http_code}' --max-time 20 https://$reg/v2/google_containers/nginx-ingress-controller/manifests/v1.3.1)"
done

echo ""
echo "===== 4. 统计：自研 blueking 镜像总可拉率（决定性的）====="
F=/root/bk72/chart-images/blueking/chart-images.txt
tot=0; ok=0
while IFS=$'\t' read -r chart ver imgs; do
  for im in $imgs; do
    case "$im" in *blueking/*|*"blueking"*) ;; *) continue;; esac
    g="${im#*://}"; g="${g#*/}"
    r2="${g%@*}"; r2="${r2%:*}"; rf="${g##*@}"; [ "$rf" = "$g" ] && rf="${g##*:}"
    tot=$((tot+1))
    T=$(curl -s --max-time 20 "https://$R/service/token?service=harbor-registry&scope=repository:$r2:pull" | grep -oE '"token":"[^"]+"' | sed 's/"token":"//;s/"$//' | head -1)
    c=$(curl -s -o /dev/null -w "%{http_code}" --max-time 25 -H "Authorization: Bearer $T" -H "Accept: application/vnd.docker.distribution.manifest.v2+json,application/vnd.oci.image.manifest.v1+json,application/vnd.docker.distribution.manifest.list.v2+json" "https://$R/v2/$r2/manifests/$rf")
    [ "$c" = "200" ] && ok=$((ok+1))
  done
done < "$F"
echo "自研 blueking 镜像: $ok / $tot 可拉"
