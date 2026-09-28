#!/usr/bin/env bash
set -uo pipefail

echo "===== 1. 监控需要的新依赖（当前集群有没有）====="
for r in bk-kafka bk-consul bk-influxdb bk-monitor bkmonitor-operator; do
  if helm list -A --short 2>/dev/null | grep -qx "$r"; then
    printf "  ✅ %-20s 已装\n" "$r"
  else
    printf "  ❌ %-20s 未装 (需新增)\n" "$r"
  fi
done

echo ""
echo "===== 2. 监控 values 文件是否存在 ====="
for f in bkmonitor-values.yaml.gotmpl bkmonitor-custom-values.yaml.gotmpl \
         kafka-values.yaml.gotmpl kafka-custom-values.yaml.gotmpl \
         consul-values.yaml.gotmpl consul-custom-values.yaml.gotmpl \
         influxdb-values.yaml.gotmpl influxdb-custom-values.yaml.gotmpl \
         bkmonitor-operator-values.yaml.gotmpl bkmonitor-operator-custom-values.yaml.gotmpl; do
  p="/root/bk72/install/blueking/environments/default/$f"
  if [ -f "$p" ]; then printf "  ✅ %-46s %s bytes\n" "$f" "$(stat -c%s "$p")"
  else printf "  ❌ %-46s 缺失\n" "$f"; fi
done

echo ""
echo "===== 3. chart 版本（version 定义）====="
grep -A30 'version:' /root/bk72/install/blueking/environments/default/version.yaml 2>/dev/null \
  | grep -iE 'monitor|kafka|consul|influxdb|operator' | sed 's/^/  /'
for f in /root/bk72/install/blueking/environments/default/*.yaml; do
  grep -iE '^\s*(bk-monitor|kafka|consul|influxdb|bkmonitor-operator-stack):' "$f" 2>/dev/null \
    | sed "s|^|  ($(basename "$f")) |"
done

echo ""
echo "===== 4. 依赖 chart tgz 是否已在本地 ====="
ls -1 /root/bk72/install/blueking/charts/ 2>/dev/null | grep -iE 'kafka|consul|influxdb' | sed 's/^/  /'

echo ""
echo "===== 5. bk-monitor chart 在 repo 里的最新版本 ====="
helm search repo blueking/bk-monitor 2>/dev/null | sed 's/^/  /'
helm search repo blueking/bkmonitor-operator-stack 2>/dev/null | sed 's/^/  /'

echo ""
echo "===== 6. presync hook 脚本（bkrepo bucket 依赖）====="
ls -la /root/bk72/install/blueking/scripts/add_bkrepo_bucket.sh 2>/dev/null | sed 's/^/  /'

echo ""
echo "===== 7. 节点剩余资源（决定能不能装）====="
kubectl top nodes 2>/dev/null | sed 's/^/  /'
