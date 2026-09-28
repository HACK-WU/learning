#!/usr/bin/env bash
set -uo pipefail
echo "===== 1. 查找 helmfile 可执行文件 ====="
for p in /usr/local/bin/helmfile /usr/bin/helmfile /root/go/bin/helmfile /opt/helmfile; do
  [ -f "$p" ] && echo "  找到: $p"
done
which helmfile 2>/dev/null || echo "  PATH 中无"
find / -maxdepth 4 -name 'helmfile' -type f 2>/dev/null | head -5

echo ""
echo "===== 2. helm 是否可用 ====="
which helm 2>/dev/null && helm version --short 2>/dev/null

echo ""
echo "===== 3. 历史命令（找之前怎么部署的）====="
ls -la /root/.bash_history 2>/dev/null && grep -iE 'helmfile|bk72|helm' /root/.bash_history 2>/dev/null | tail -20

echo ""
echo "===== 4. 部署目录里的脚本 ====="
ls /root/bk72/ 2>/dev/null | head -20
find /root/bk72 -maxdepth 2 -name '*.sh' 2>/dev/null | head -10

echo ""
echo "===== 5. 之前日志（若有）====="
ls -la /tmp/*.log 2>/dev/null | head -5
