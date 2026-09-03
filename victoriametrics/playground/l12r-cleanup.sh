#!/bin/bash
# 清理本次补充实验自建的测试容器与卷
# ⚠️ 只删除 l12r 前缀的自建资源，不动任何既有学习容器
echo "=== 清理课 12 补充实验的自建测试容器 ==="
for c in vm-l12r-del vm-l12r-snap vm-l12r-A vm-l12r-B; do
  if docker ps -a --format '{{.Names}}' | grep -qx "$c"; then
    docker rm -f "$c" >/dev/null 2>&1 && echo "  ✅ 已删除容器 $c"
  else
    echo "  ℹ️ 容器 $c 不存在，跳过"
  fi
done

echo ""
echo "=== 清理自建卷 ==="
for v in l12r_del_vol l12r_snap_vol vm-l12r-A_vol vm-l12r-B_vol; do
  if docker volume ls --format '{{.Name}}' | grep -qx "$v"; then
    docker volume rm "$v" >/dev/null 2>&1 && echo "  ✅ 已删除卷 $v"
  else
    echo "  ℹ️ 卷 $v 不存在，跳过"
  fi
done

echo ""
echo "=== 确认既有学习容器完好（未被误删） ==="
for c in vm-learn prom-learn vmstorage-learn vmstorage-learn2 vminsert-learn vmselect-learn vmagent-learn vmalert-learn alertmanager-learn doris-minio; do
  st=$(docker ps --format '{{.Names}} {{.Status}}' | grep "^${c} " | head -1)
  if [ -n "$st" ]; then
    echo "  ✅ $st"
  else
    echo "  ⚠️ $c 未运行"
  fi
done

echo ""
echo "=== 确认集群租户 4242 的迁移数据保留（作为实验证据） ==="
curl -s "http://localhost:8481/select/4242/prometheus/api/v1/series/count" | head -c 100
echo ""
