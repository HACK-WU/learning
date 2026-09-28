#!/usr/bin/env bash
set -uo pipefail
NS=blueking

echo "===== 1. 官方模块清单（bk-config 目录 = 真正的应用模块）====="
ls -1 /root/bk72/install/bk-config/ 2>/dev/null | sed 's/^/  /'

echo ""
echo "===== 2. 集群已安装的 release ====="
helm list -n "$NS" --short 2>/dev/null | sort | sed 's/^/  /'

echo ""
echo "===== 3. 差异（官方模块 - 已装）====="
OFFICIAL=$(ls -1 /root/bk72/install/bk-config/ 2>/dev/null | sort)
INSTALLED=$(helm list -n "$NS" --short 2>/dev/null | sort)
echo "  [官方模块中有，但集群未装的 release 名] :"
comm -23 <(echo "$OFFICIAL") <(echo "$INSTALLED") | while read -r c; do
  [ -n "$c" ] && printf "    ❌ %s\n" "$c"
done

echo ""
echo "===== 4. 逐个关键模块：官方配置存在性 + 集群安装状态 ====="
printf "  %-22s %-14s %-10s %s\n" "模块" "官方配置" "集群已装" "说明"
printf "  %-22s %-14s %-10s %s\n" "----" "--------" "--------" "----"
for c in bk_nodeman bk_monitor bk_monitorv3 bk_job bk_log bk_log_search bk_cmdb bk_iam bk_paas bk_user bk_gse bk_repo bk_apigateway bk_ssm bkauth bk_applog bk_lesscode bk_ci bk_cmdb bk_dbm bk_hcm bk_codecc; do
  hascfg="无"
  [ -d "/root/bk72/install/bk-config/$c" ] && hascfg="有"
  inst="未装"
  echo "$INSTALLED" | grep -qx "$c" && inst="已装"
  # 也接受下划线换中划线
  c2=$(echo "$c" | tr '_' '-')
  echo "$INSTALLED" | grep -qx "$c2" && inst="已装"
  printf "  %-22s %-14s %-10s\n" "$c" "$hascfg" "$inst"
done

echo ""
echo "===== 5. 确认 nodeman / monitor 在官方体系里的位置 ====="
find /root/bk72 -maxdepth 5 -type d \( -name "*nodeman*" -o -name "*monitor*" \) 2>/dev/null | head -20 | sed 's/^/  /'

echo ""
echo "===== 6. helm repo 里 bk-nodeman / bk-monitor 是否可获取 ====="
helm search repo blueking/ 2>/dev/null | grep -iE 'nodeman|monitor|job|log|lesscode' | sed 's/^/  /'
