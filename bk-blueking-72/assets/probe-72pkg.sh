#!/usr/bin/env bash
echo "=== 1. 蓝鲸 Helm repo 可达性 (hub.bktencent.com/chartrepo) ==="
timeout 25 curl -sS -o /dev/null -w "chartrepo HTTP=%{http_code}\n" https://hub.bktencent.com/chartrepo/bkce/index.yaml 2>&1
timeout 25 curl -sS -k "https://hub.bktencent.com/chartrepo/bkce/index.yaml" 2>&1 | head -c 600

echo ""
echo ""
echo "=== 2. 文件站: 尝试列 7.2 部署包 ==="
timeout 25 curl -sS -o /dev/null -w "bkopen HTTP=%{http_code}\n" "https://bkopen-1252002024.file.myqcloud.com/" 2>&1

echo ""
echo "=== 3. 官方下载页可达性 ==="
timeout 25 curl -sS -o /dev/null -w "bk下载页 HTTP=%{http_code}\n" "https://bk.tencent.com/s-mart/downloads" 2>&1

echo ""
echo "=== 4. WSL 是否支持 systemd (7.2 kubeasz 部署需要) ==="
ps -p 1 -o comm= 2>/dev/null
if [ "$(ps -p 1 -o comm=)" = "systemd" ]; then echo "systemd: 是"; else echo "systemd: 否 (PID1=$(ps -p 1 -o comm=))"; fi

echo ""
echo "=== 5. swap 现状 (7.2 要求关闭) ==="
free -h | grep -i swap
