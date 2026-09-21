#!/usr/bin/env bash
echo "########## 1. K8s 工具链 ##########"
for t in docker kubectl kind minikube helm consul-k8s; do
  if command -v $t >/dev/null 2>&1; then
    printf "  %-12s 已安装  " "$t"
    case $t in
      docker) docker version --format '{{.Server.Version}}' 2>&1 | head -1 ;;
      kubectl) kubectl version --client=true -o yaml 2>/dev/null | grep gitVersion | head -1 | awk '{print $2}' ;;
      kind) kind version 2>&1 | head -1 ;;
      minikube) minikube version --short 2>&1 | head -1 ;;
      helm) helm version --short 2>&1 | head -1 ;;
      *) echo "" ;;
    esac
  else
    printf "  %-12s ❌ 未安装\n" "$t"
  fi
done

echo
echo "########## 2. 资源 ##########"
echo "  内存:"; free -h | sed -n '2p' | sed 's/^/    /'
echo "  CPU 核数: $(nproc)"
echo "  磁盘:"; df -h / | tail -1 | sed 's/^/    /'

echo
echo "########## 3. 多 IP 绑定能力（多 DC 前提）##########"
python3 - <<'PYEOF'
import socket
for ip in ["127.0.0.1","127.0.1.1","127.0.2.1","127.0.10.1","127.0.20.1"]:
    s = socket.socket()
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        s.bind((ip, 19999))
        print(f"  {ip:14s} 可绑定 ✅")
    except Exception as e:
        print(f"  {ip:14s} 失败: {e}")
    s.close()
PYEOF

echo
echo "########## 4. 当前 consul 进程与端口 ##########"
echo "  consul 进程数 = $(pgrep -fc 'consul agent' 2>/dev/null || echo 0)"
echo "  监听端口:"; ss -lntp 2>/dev/null | grep -E ':(830[0-9]|850[0-9]|930[0-9])' | awk '{print "    "$4}' | sort -u
