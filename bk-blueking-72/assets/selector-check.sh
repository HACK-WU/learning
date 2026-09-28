#!/usr/bin/env bash
cd /root/bk72/install/blueking 2>/dev/null || exit 1
echo "=== release -> seq label 映射 ==="
awk '/^  - name:/{n=$3} /seq:/{if(n!=""){printf "  %-28s %s\n", n, $2; n=""}}' base-blueking.yaml.gotmpl
echo ""
echo "=== monitor 相关 gotmpl 内容 ==="
for f in 04-bkmonitor.yaml.gotmpl monitor.yaml.gotmpl monitor-storage.yaml.gotmpl; do
  echo "  --- $f ---"
  sed 's/^/    /' "$f" 2>&1 | head -18
done
echo ""
echo "=== helmfile 是否可用 ==="
which helmfile 2>&1 | sed 's/^/  /'
helmfile version 2>&1 | head -2 | sed 's/^/  /'
