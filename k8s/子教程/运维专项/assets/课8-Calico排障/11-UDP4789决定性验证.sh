#!/usr/bin/env bash
set -o pipefail

CP1=192.168.122.19
W1=192.168.122.54
SSHOPT="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"

echo "########## 决定性验证：UDP 4789 基础连通性 ##########"
echo "（若 VXLAN 端口不通，任何 VXLAN 封装方案都无效）"

echo "--- [1] w1 上监听 UDP 4789 ---"
ssh $SSHOPT k8s@$W1 "sudo -n timeout 8 tcpdump -i enp1s0 -nn -c 5 'udp port 4789' 2>&1 | tail -3 &" 2>&1 &
sleep 1

echo "--- [2] cp1 向 w1 发 UDP 4789 测试包 ---"
ssh $SSHOPT k8s@$CP1 "sudo -n bash -c 'echo VXLAN_TEST | timeout 3 nc -u -w1 $W1 4789 2>&1'; echo nc_exit=\$?" 2>&1
sleep 8

echo ""
echo "--- [3] 对比：普通 UDP 端口（如 9999）是否可达 ---"
ssh $SSHOPT k8s@$W1 "sudo -n nohup timeout 8 nc -u -l -p 9999 > /tmp/udp9999.log 2>&1 &" 2>&1
sleep 2
ssh $SSHOPT k8s@$CP1 "echo PLAIN_UDP | timeout 3 nc -u -w1 $W1 9999 2>&1; echo exit=\$?" 2>&1
sleep 7
ssh $SSHOPT k8s@$W1 "sudo -n cat /tmp/udp9999.log 2>&1" 2>&1

echo ""
echo "########## iptables FORWARD 链检查（决定性）##########"
for NODE_IP in $CP1 $W1; do
echo "======== $NODE_IP ========"
ssh $SSHOPT k8s@$NODE_IP 'sudo -n bash -s' <<'EOS' 2>&1
echo "--- FORWARD 链默认策略 ---"
iptables -L FORWARD -n -v 2>/dev/null | head -3
echo "--- FORWARD 链中 cali 相关规则及命中计数 ---"
iptables -L FORWARD -n -v 2>/dev/null | grep -i cali | head -8
echo "--- cali-FORWARD 链内容 ---"
iptables -L cali-FORWARD -n -v 2>/dev/null | head -12
EOS
done
