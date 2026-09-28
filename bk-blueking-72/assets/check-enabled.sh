#!/usr/bin/env bash
# 用途：确认哪些组件真正启用 + 各 chart 的默认资源需求
set -uo pipefail
B=/root/bk72/install/blueking
E=$B/environments/default

echo "===== 1. custom-values 文件是否存在 ====="
for c in mysql mysql8 rabbitmq redis redis-cluster mongodb elasticsearch zookeeper etcd; do
  printf "%-16s " "$c"
  [ -f "$E/$c-custom-values.yaml.gotmpl" ] && echo -n "custom:有 " || echo -n "custom:无 "
  [ -f "$E/$c-values.yaml.gotmpl" ] && echo "values:有" || echo "values:无"
done

echo ""
echo "===== 2. 启用开关 bitnami*.enabled 在哪里定义 ====="
grep -rn "bitnamiMysql\|bitnamiRedis\|bitnamiMongodb\|bitnamiElasticsearch\|bitnamiEtcd\|bitnamiZookeeper\|bitnamiRabbitmq" "$E/values.yaml" 2>/dev/null | head -20

echo ""
echo "===== 3. values.yaml 里 storage 相关段落 ====="
grep -nA20 -E '^bitnami|^  #.*storage|storage:' "$E/values.yaml" 2>/dev/null | head -40
