#!/usr/bin/env bash
set -uo pipefail

echo "===== 1. monitor 相关 helmfile 内容 ====="
for f in /root/bk72/install/blueking/04-bkmonitor.yaml.gotmpl \
         /root/bk72/install/blueking/monitor.yaml.gotmpl \
         /root/bk72/install/blueking/monitor-storage.yaml.gotmpl \
         /root/bk72/install/blueking/04-bkmonitor-operator.yaml.gotmpl; do
  [ -f "$f" ] || continue
  echo ""
  echo "  ########## $(basename "$f") ##########"
  cat "$f" 2>/dev/null | sed 's/^/  /'
done

echo ""
echo "===== 2. base.yaml.gotmpl 里定义的 release（看主清单）====="
grep -E '^\s*-\s*name:|^\s*chart:|^\s*version:' /root/bk72/install/blueking/base.yaml.gotmpl 2>/dev/null | head -40 | sed 's/^/  /'

echo ""
echo "===== 3. base-blueking.yaml.gotmpl 的 release 清单 ====="
grep -E '^\s*-\s*name:|^\s*chart:' /root/bk72/install/blueking/base-blueking.yaml.gotmpl 2>/dev/null | head -40 | sed 's/^/  /'

echo ""
echo "===== 4. 所有 gotmpl 文件列表（完整模块清单）====="
ls -1 /root/bk72/install/blueking/*.gotmpl 2>/dev/null | xargs -n1 basename | sed 's/^/  /'
