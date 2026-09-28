#!/usr/bin/env bash
echo "=== VERSION.YAML (组件版本清单) ==="
cat /root/bk72/install/blueking/environments/default/version.yaml 2>&1 | sed 's/^/  /'
echo ""
echo "=== HELM REPO 详情（下载来源） ==="
helm repo list 2>&1 | sed 's/^/  /'
echo ""
echo "=== blueking repo 索引地址推导 ==="
echo "  repo:      https://hub.bktencent.com/chartrepo/blueking"
echo "  index.yaml: https://hub.bktencent.com/chartrepo/blueking/index.yaml"
echo ""
echo "=== 已装 release 的 chart 版本 ==="
helm list -n blueking --no-headers 2>/dev/null | awk '{printf "  %-28s %-12s\n", $1, $5}' | sort
