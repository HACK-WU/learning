#!/bin/bash
# 课 10 开课检查：集群状态 + 课 10 定义
echo "=== 容器状态 ==="
docker ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' --filter 'name=vm' 2>&1

echo
echo "=== 各组件健康检查 ==="
for pair in "vminsert-learn:8480" "vminsert-learn2:8488" "vmselect-learn:8481" \
            "vmsel-n1:8485" "vmsel-n2:8486" "vmsel-dedup:8487" "vmsel-d5:8489" \
            "vmstorage-learn:8482" "vmstorage-learn2:8492" "vm-learn:8428"; do
  name="${pair%%:*}"; port="${pair##*:}"
  c=$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "http://localhost:$port/health" 2>/dev/null)
  echo "  $name (port $port): HTTP $c"
done

echo
echo "=== 课 10 定义（课程目录）==="
grep -n -A8 '课 10' /mnt/d/projects/learning/victoriametrics/02-课程目录.md 2>&1

echo
echo "=== 阶段 4 概览中的课 10 ==="
grep -n -A10 '课 10' '/mnt/d/projects/learning/victoriametrics/stages/4-怎么横向扩展/README.md' 2>&1

echo
echo "=== vmauth 镜像可用性 ==="
docker images | grep -i vmauth || echo "  (本地无 vmauth 镜像)"

echo
echo "=== 端口占用检查（vmauth 计划用 8427）==="
for p in 8427 8428 8480 8481; do
  r=$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 "http://localhost:$p/health" 2>/dev/null)
  echo "  port $p -> HTTP $r"
done

echo
echo "=== 本机资源 ==="
echo "  CPU: $(nproc) 核"
free -m 2>/dev/null | head -2

echo
echo "=== 现有测试序列名（前 20 个）==="
curl -s --max-time 20 'http://localhost:8481/select/0/prometheus/api/v1/label/__name__/values' 2>/dev/null \
  | python3 -c 'import json,sys
v=json.load(sys.stdin).get("data",[])
print("  总计:", len(v))
print("  ", " ".join(v[:20]))' 2>&1
