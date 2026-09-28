#!/usr/bin/env bash
set -uo pipefail
NS=blueking

echo "===== 1. 官方 bk72/install/blueking/charts 完整清单 ====="
ls -1 /root/bk72/install/blueking/charts 2>/dev/null | sed 's/^/  /'

echo ""
echo "===== 2. 官方 install 配置里启用了哪些模块 ====="
for f in /root/bk72/install/blueking/*.yaml /root/bk72/install/blueking/values*.yaml; do
  [ -f "$f" ] || continue
  echo "  --- $(basename "$f") ---"
  grep -oE '^[[:space:]]{0,4}[a-zA-Z0-9_-]+:' "$f" 2>/dev/null | tr -d ' :' | sort -u | head -60 | sed 's/^/    /'
done

echo ""
echo "===== 3. 对比：官方有 + 集群已装 ====="
OFFICIAL=$(ls -1 /root/bk72/install/blueking/charts 2>/dev/null | sort)
INSTALLED=$(helm list -n "$NS" --short 2>/dev/null | sort)
echo "  官方 chart 总数: $(echo "$OFFICIAL" | grep -c .)"
echo "  集群已装总数:   $(echo "$INSTALLED" | grep -c .)"
echo ""
echo "  [官方有但未安装] —— 这些是缺失组件："
comm -23 <(echo "$OFFICIAL") <(echo "$INSTALLED") | while read -r c; do
  [ -n "$c" ] && printf "    ❌ %s\n" "$c"
done

echo ""
echo "  [集群已装] —— 对照用："
echo "$INSTALLED" | while read -r c; do [ -n "$c" ] && printf "    ✅ %s\n" "$c"; done

echo ""
echo "===== 4. 关键组件存在性确认（用户关心的）====="
for c in bk-nodeman bk-monitor bk-job bk-log bk-cmdb bk-iam bk-paas bk-user bk-gse bk-repo bk-apigateway bk-ssm bkauth bk-applog bk-lesscode bk-ci bk-codecc bk-hcm bk-dbm; do
  if echo "$INSTALLED" | grep -qx "$c"; then
    st=$(helm list -n "$NS" 2>/dev/null | awk -v n="$c" '$1==n{print $5}')
    printf "    ✅ %-18s (helm status: %s)\n" "$c" "$st"
  else
    OFF=$(ls -1 /root/bk72/install/blueking/chars 2>/dev/null | grep -qx "$c" && echo "官方有" || echo "官方无")
    printf "    ❌ %-18s 未安装  (%s)\n" "$c" "$OFF"
  fi
done
