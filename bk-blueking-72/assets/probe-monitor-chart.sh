#!/usr/bin/env bash
set -uo pipefail

echo "===== 1. bk-config 各目录真实内容（判断是不是 chart 配置）====="
for d in /root/bk72/install/bk-config/*/; do
  n=$(basename "$d")
  c=$(ls -1 "$d" 2>/dev/null | wc -l)
  y=$(ls "$d" 2>/dev/null | grep -cE '\.ya?ml$')
  t=$(ls "$d" 2>/dev/null | head -5 | tr '\n' ',')
  printf "  %-18s files=%-3s yaml=%-3s  %s\n" "$n" "$c" "$y" "$t"
done

echo ""
echo "===== 2. 找 helmfile 定义（真正的 release 清单）====="
find /root/bk72/install -maxdepth 3 \( -name 'helmfile*' -o -name '*.yaml.gotmpl' \) 2>/dev/null | head -20 | sed 's/^/  /'
ls -la /root/bk72/install/ 2>/dev/null | head -25 | sed 's/^/  /'

echo ""
echo "===== 3. 全局搜 monitor 相关 helmfile/values ====="
find /root/bk72 -maxdepth 4 -type f \( -name '*.yaml' -o -name '*.gotmpl' \) 2>/dev/null \
  | xargs grep -l -iE 'monitor' 2>/dev/null | head -15 | sed 's/^/  /'

echo ""
echo "===== 4. bk_monitorv3 目录详情（只有图片?）====="
ls -la /root/bk72/install/bk-config/bk_monitorv3/ 2>/dev/null | sed 's/^/  /'

echo ""
echo "===== 5. 类似目录对比：bk_nodeman 有啥 ====="
ls -la /root/bk72/install/bk-config/bk_nodeman/ 2>/dev/null | sed 's/^/  /'
