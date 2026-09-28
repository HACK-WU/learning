#!/usr/bin/env bash
set -uo pipefail
{
echo "===== 1. 节点管理相关 helmfile ====="
ls /root/bk72/install/blueking/*.gotmpl 2>/dev/null | sed 's/^/  /'

echo ""
echo "===== 2. base-blueking.yaml.gotmpl 里有没有 nodeman ====="
grep -inE 'nodeman|node-man|node_manager' /root/bk72/install/blueking/base-blueking.yaml.gotmpl 2>/dev/null | head -20 | sed 's/^/  /'

echo ""
echo "===== 3. version.yaml 里 nodeman 版本 ====="
grep -inE 'nodeman|node-man' /root/bk72/install/blueking/environments/default/version.yaml 2>/dev/null | head -10 | sed 's/^/  /'

echo ""
echo "===== 4. helm repo 里有没有 bk-nodeman chart ====="
helm search repo blueking/ 2>/dev/null | grep -iE 'nodeman|node' | head -10 | sed 's/^/  /'

echo ""
echo "===== 5. 所有含 nodeman 的 gotmpl ====="
grep -rlnE 'nodeman' /root/bk72/install/blueking/ 2>/dev/null | head -10 | sed 's/^/  /'
} > /root/survey-nodeman.txt 2>&1
cat /root/survey-nodeman.txt
