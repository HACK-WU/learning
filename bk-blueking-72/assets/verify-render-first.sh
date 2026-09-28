#!/usr/bin/env bash
# 渲染校验：确认 repo 缺失问题已解决
set -uo pipefail
export PATH=/root/bk72/install/bin:$PATH
HF=/root/bk72/install/bin/helmfile
B=/root/bk72/install/blueking

cd "$B" || exit 1

echo "===== 渲染 seq=first ====="
$HF -f base.yaml.gotmpl -l seq=first template > /tmp/render-first.yaml 2>/tmp/render-err.txt
rc=$?
echo "  退出码: $rc"
echo "  输出行数: $(wc -l < /tmp/render-first.yaml)"
echo "  输出字节: $(wc -c < /tmp/render-first.yaml)"

echo ""
echo "===== 错误信息（若有）====="
grep -iE '^Error|error:|not found' /tmp/render-err.txt | head -5

if [ $rc -eq 0 ]; then
  echo ""
  echo "===== 渲染出的资源统计 ====="
  grep -c '^kind:' /tmp/render-first.yaml | xargs echo "  资源对象数:"
  grep '^kind:' /tmp/render-first.yaml | sort | uniq -c | sort -rn | head -8
  echo ""
  echo "===== 涉及的镜像（判断拉取量）====="
  grep -oE 'image: [^ ]+' /tmp/render-first.yaml | sed 's/image: //' | sort -u | head -15
else
  echo "  ❌ 渲染仍失败，详情:"
  tail -25 /tmp/render-err.txt
fi
