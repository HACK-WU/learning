#!/usr/bin/env bash
set -o pipefail

CP1=192.168.122.19
W1=192.168.122.54
SSH_KEY=/root/.ssh/id_rsa

echo "=== [1/5] 准备 SSH 密钥 ==="
if [ ! -f "$SSH_KEY" ]; then
  ssh-keygen -t rsa -b 2048 -f "$SSH_KEY" -N '' -q 2>&1
  echo "密钥已生成"
else
  echo "密钥已存在"
fi
ls -l "$SSH_KEY" "$SSH_KEY.pub" 2>&1

echo ""
echo "=== [2/5] 测试 SSH 连通（密码方式先探）==="
which sshpass >/dev/null 2>&1 || apt-get install -y -qq sshpass 2>&1 | tail -2
echo "sshpass: $(which sshpass)"

for NODE_IP in $CP1 $W1; do
  echo "--- $NODE_IP ---"
  for i in $(seq 1 10); do
    if sshpass -p 'k8s1234' ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o UserKnownHostsFile=/dev/null k8s@$NODE_IP 'echo SSH_OK' 2>/dev/null | grep -q SSH_OK; then
      echo "SSH 可达"
      break
    fi
    sleep 5
  done
done

echo ""
echo "=== [3/5] 分发密钥 ==="
for NODE_IP in $CP1 $W1; do
  echo "--- copy-id to $NODE_IP ---"
  sshpass -p 'k8s1234' ssh-copy-id -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null k8s@$NODE_IP 2>&1 | tail -3
done

echo ""
echo "=== [4/5] 验证：真虚机判定（内核/systemd/主机名）==="
for NODE_IP in $CP1 $W1; do
  echo "######## $NODE_IP ########"
  ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o UserKnownHostsFile=/dev/null k8s@$NODE_IP <<'EOS' 2>&1
echo "hostname   : $(hostname)"
echo "内核       : $(uname -r)"
echo "PID1       : $(ps -p 1 -o comm=)"
echo "systemd    : $(systemctl is-system-running 2>&1)"
echo "OS         : $(. /etc/os-release && echo $PRETTY_NAME)"
echo "CPU        : $(nproc) 核"
echo "内存       : $(free -g | awk '/Mem:/ {print $2}') GB"
echo "虚拟化类型 : $(systemd-detect-virt 2>&1)"
echo "IP         : $(hostname -I | tr -d '\n')"
echo "swap       : $(swapon --show | wc -l) 个(0=已关闭,符合kubeadm要求)"
EOS
done

echo ""
echo "=== [5/5] 节点互通 ==="
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null k8s@$CP1 "ping -c 2 -W 2 $W1 2>&1 | tail -3" 2>&1
