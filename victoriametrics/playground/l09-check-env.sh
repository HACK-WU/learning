#!/bin/bash
# 课 9 开课检查：集群是否还活着 + 课 9 定义
echo "=== 容器状态 ==="
docker ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' --filter 'name=vm' 2>&1

echo
echo "=== 集群各组件健康检查 ==="
for pair in "vminsert-learn:8480" "vmselect-learn:8481" "vmstorage-learn:8482" "vmstorage-learn2:8492" "vm-learn:8428"; do
  name="${pair%%:*}"; port="${pair##*:}"
  c=$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "http://localhost:$port/health" 2>/dev/null)
  echo "  $name (port $port): HTTP $c"
done

echo
echo "=== 课 9 定义（课程目录）==="
grep -n -A6 '课 9' /mnt/d/projects/learning/victoriametrics/02-课程目录.md 2>&1

echo
echo "=== 当前 vminsert / vmselect 启动参数 ==="
echo -n "  vminsert: "
docker inspect vminsert-learn --format '{{.Args}}' 2>&1
echo -n "  vmselect: "
docker inspect vmselect-learn --format '{{.Args}}' 2>&1

echo
echo "=== 各 vmstorage tsid 基线 ==="
echo -n "  vmstorage1(8482): "
curl -s --max-time 15 'http://localhost:8482/metrics' 2>/dev/null \
  | grep 'vm_cache_entries{type="storage/tsid"' | head -1 | awk '{print $2}'
echo -n "  vmstorage2(8492): "
curl -s --max-time 15 'http://localhost:8492/metrics' 2>/dev/null \
  | grep 'vm_cache_entries{type="storage/tsid"' | head -1 | awk '{print $2}'

echo
echo "=== 磁盘占用 ==="
cd /mnt/d/projects/learning/victoriametrics/playground 2>/dev/null && {
  echo "  单节点 data/:     $(du -sh data 2>/dev/null | cut -f1)"
  echo "  集群 storage/:    $(du -sh cluster-data/storage 2>/dev/null | cut -f1)"
  echo "  集群 storage2/:   $(du -sh cluster-data/storage2 2>/dev/null | cut -f1)"
}

echo
echo "=== 本机资源 ==="
echo "  CPU: $(nproc) 核"
free -m 2>/dev/null | head -2
