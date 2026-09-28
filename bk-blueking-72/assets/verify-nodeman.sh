#!/usr/bin/env bash
set -uo pipefail
{
echo "===== 1. base-blueking.yaml.gotmpl 里所有 release 名 ====="
grep -E '^\s+- name:' /root/bk72/install/blueking/base-blueking.yaml.gotmpl 2>/dev/null | sed 's/.*name: *//' | sort | sed 's/^/  /'

echo ""
echo "===== 2. 集群里已安装的 release ====="
helm list -A --short 2>/dev/null | awk '{print $1}' | sort | sed 's/^/  /'

echo ""
echo "===== 3. base-blueking 里有但集群里没有的（真缺失）====="
comm -23 \
  <(grep -E '^\s+- name:' /root/bk72/install/blueking/base-blueking.yaml.gotmpl 2>/dev/null | sed 's/.*name: *//' | sort) \
  <(helm list -A --short 2>/dev/null | awk '{print $1}' | sort) | sed 's/^/  /'

echo ""
echo "===== 4. bk-nodeman 是否已在集群 ====="
helm list -A --short 2>/dev/null | grep -E 'nodeman' | sed 's/^/  /' || echo "  (bk-nodeman 未安装)"
kubectl get pods -n blueking --no-headers 2>/dev/null | grep -i 'nodeman' | sed 's/^/  /' || echo "  (无 nodeman Pod)"

echo ""
echo "===== 5. nodeman 版本阻塞确认 ====="
echo "  version.yaml 指定: $(grep 'bk-nodeman' /root/bk72/install/blueking/environments/default/version.yaml)"
echo "  repo 可用版本:"
helm search repo blueking/bk-nodeman --versions 2>/dev/null | head -5 | sed 's/^/    /'
} > /root/verify-nodeman.txt 2>&1
cat /root/verify-nodeman.txt
