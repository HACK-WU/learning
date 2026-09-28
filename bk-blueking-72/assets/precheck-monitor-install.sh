#!/usr/bin/env bash
set -uo pipefail
BK=/root/bk72/install/blueking

echo "===== 1. helmfile 是否可用 ====="
which helmfile 2>/dev/null && helmfile version 2>/dev/null | head -2 || echo "  helmfile 不在 PATH"
ls -la /root/bk72/install/bin/helmfile 2>/dev/null | sed 's/^/  /'
/root/bk72/install/bin/helmfile version 2>/dev/null | head -2 | sed 's/^/  /'

echo ""
echo "===== 2. custom.yaml / env.yaml 是否存在 ====="
for f in environments/default/custom.yaml env.yaml defaults.yaml; do
  [ -f "$BK/$f" ] && echo "  OK   $f" || echo "  MISS $f"
done

echo ""
echo "===== 3. 缺失的 custom-values 文件（阻塞点）====="
for f in bkmonitor-custom-values.yaml.gotmpl \
         kafka-custom-values.yaml.gotmpl \
         consul-custom-values.yaml.gotmpl \
         influxdb-custom-values.yaml.gotmpl \
         bkmonitor-operator-custom-values.yaml.gotmpl; do
  [ -f "$BK/environments/default/$f" ] && echo "  OK   $f" || echo "  MISS $f"
done

echo ""
echo "===== 4. 尝试 helmfile 渲染（dry-run，不改集群）====="
cd "$BK" 2>/dev/null || { echo "  无法进入 $BK"; exit 1; }
timeout 120 /root/bk72/install/bin/helmfile -f monitor-storage.yaml.gotmpl build 2>&1 | head -30 | sed 's/^/  /'
echo "  --- build exit: $? ---"
