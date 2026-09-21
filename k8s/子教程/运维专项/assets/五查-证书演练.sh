#!/usr/bin/env bash
# ③ 证书查：有效期取数 + 过期故障「安全模拟」
#
# ⚠️ 设计原则：不真改系统时间（改时间会污染 etcd/证书校验/Prometheus，风险大且难还原）
#    改用「openssl 解析证书 + 自制短命证书」来演示判据与现象，全程可逆、可一键清理
#
# 安全声明：
#   - A/B/C 段：纯只读（解析现有证书有效期），不改任何东西
#   - D 段：在 /tmp 下自制 1 天有效的测试证书（不碰 /etc/kubernetes/pki 任何文件）
#   - E 段：演示「剩余天数 → 动作」的判据表（纯 echo）
#   - 不重启任何组件、不改系统时间、不动真实证书
set -uo pipefail

hr() { printf '\n========== %s ==========\n' "$*"; }
CP=$(docker ps --format '{{.Names}}' 2>/dev/null | grep control-plane | head -1)
echo "控制面容器: ${CP:-未找到}"

hr 'A. kubeadm 视角：组件证书 vs CA（两个数量级）'
docker exec "$CP" kubeadm certs check-expiration 2>&1 | grep -vE 'Reading configuration|Use .kubeadm init' | head -25

hr 'B. openssl 视角：单张证书的精确有效期（不依赖 kubeadm）'
docker exec "$CP" sh -c '
for f in apiserver apiserver-kubelet-client front-proxy-client; do
  printf "%-26s " "$f"
  openssl x509 -in /etc/kubernetes/pki/$f.crt -noout -enddate 2>/dev/null | sed "s/notAfter=//"
done
printf "%-26s " "ca"
openssl x509 -in /etc/kubernetes/pki/ca.crt -noout -enddate 2>/dev/null | sed "s/notAfter=//"
'

hr 'C. 换算剩余天数（这才是告警规则该盯的数）'
docker exec "$CP" sh -c '
now=$(date +%s)
for f in apiserver apiserver-kubelet-client front-proxy-client ca; do
  end=$(openssl x509 -in /etc/kubernetes/pki/$f.crt -noout -enddate 2>/dev/null | sed "s/notAfter=//")
  [ -z "$end" ] && continue
  # GNU date 可直接解析 RFC2822
  endts=$(date -d "$end" +%s 2>/dev/null)
  [ -z "$endts" ] && continue
  days=$(( (endts - now) / 86400 ))
  printf "%-26s 剩余 %s 天  (过期于 %s)\n" "$f" "$days" "$end"
done
'

hr 'D. 过期现象模拟：自制 1 天有效的证书，看 openssl 如何判定'
docker exec "$CP" sh -c '
mkdir -p /tmp/certdrill && cd /tmp/certdrill
# 自制一张「今天过期」的自签证书（不碰真实 PKI）
openssl req -x509 -newkey rsa:2048 -nodes -keyout t.key -out t.crt -days 1 \
  -subj "/CN=drill-expired" 2>/dev/null
echo "--- 这张自制证书的有效期 ---"
openssl x509 -in t.crt -noout -dates
echo
echo "--- 用 CA 校验真实 apiserver 证书（应 OK）---"
openssl verify -CAfile /etc/kubernetes/pki/ca.crt /etc/kubernetes/pki/apiserver.crt 2>&1
echo
echo "--- 用错误的 CA 校验（应失败，模拟信任链断裂）---"
openssl verify -CAfile /tmp/certdrill/t.crt /etc/kubernetes/pki/apiserver.crt 2>&1
'

hr 'E. 判据表：剩余天数 → 动作'
cat <<'EOF'
剩余天数    状态        动作
> 90 天     正常        仅台账登记
30~90 天    预警        排期续期（kubeadm certs renew all）
< 30 天     紧急        立即续期，并验证组件已重载
< 0 天      已过期      集群全挂：全部请求 401 / x509
EOF

hr 'F. 清理（只删自建的 /tmp 目录，真实证书未触碰）'
docker exec "$CP" sh -c 'rm -rf /tmp/certdrill && echo "已清理 /tmp/certdrill"'
echo '--- 确认真实证书完好 ---'
docker exec "$CP" sh -c 'ls -la /etc/kubernetes/pki/apiserver.crt; openssl x509 -in /etc/kubernetes/pki/apiserver.crt -noout -enddate'

hr '证书演练结束（集群状态未改变）'
