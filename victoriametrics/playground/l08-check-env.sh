#!/bin/bash
# 课 8 开课检查：单节点现状 + 集群镜像可用性 + 端口规划
Q() { curl -s --max-time 15 --data-urlencode "query=$1" http://localhost:8428/api/v1/query; }

echo "=============================================="
echo " E1 现有容器与端口占用"
echo "=============================================="
docker ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' 2>&1

echo
echo "=============================================="
echo " E2 已被占用的端口（避免集群端口冲突）"
echo "=============================================="
for p in 8428 8480 8481 8482 8483 8484 9090 2003 4242; do
  r=$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 "http://localhost:$p/" 2>/dev/null)
  echo "  port $p -> HTTP $r"
done

echo
echo "=============================================="
echo " E3 本机资源（够不够跑集群）"
echo "=============================================="
echo "  CPU 核数: $(nproc)"
echo "  内存:"
free -m 2>/dev/null | head -2
echo "  磁盘剩余:"
df -h /mnt/d 2>/dev/null | tail -1

echo
echo "=============================================="
echo " E4 Docker 镜像：能否拉到集群版"
echo "=============================================="
echo "  -- 已有哪些 victoriametrics 镜像 --"
docker images 2>&1 | grep -i victoria || echo "    无 victoriametrics 镜像缓存"

echo
echo "  -- 尝试拉取 cluster 版（这是课 8 的关键前提）--"
timeout 120 docker pull victoriametrics/victoria-metrics:v1.151.0-cluster 2>&1 | tail -5

echo
echo "=============================================="
echo " E5 如果拉不到，退路是什么"
echo "=============================================="
echo "  方案 A: 用 :latest 单节点镜像里的 cluster 二进制"
docker run --rm --entrypoint /bin/sh victoriametrics/victoria-metrics:latest \
  -c 'ls /victoria-metrics* 2>/dev/null; which vminsert vmselect vmstorage 2>/dev/null' 2>&1 | head -10

echo
echo "  方案 B: 检查 vmutils 镜像（官方工具集）"
timeout 60 docker pull victoriametrics/vmutils:v1.151.0 2>&1 | tail -3
docker run --rm --entrypoint /bin/sh victoriametrics/vmutils:v1.151.0 \
  -c 'ls /vmutils* 2>/dev/null | head -20' 2>&1 | head -10

echo
echo "=============================================="
echo " E6 单节点当前基线（课 8 要回答『什么时候不够』）"
echo "=============================================="
echo "  totalSeries:"
curl -s --max-time 20 'http://localhost:8428/api/v1/status/tsdb' \
  | python3 -c 'import json,sys; print("    ", json.load(sys.stdin)["data"].get("totalSeries"))' 2>/dev/null
echo "  RSS:"
Q 'process_resident_memory_bytes' | python3 -c 'import json,sys
d=json.load(sys.stdin)["data"]["result"]
print("    %.2f MB" % (float(d[0]["value"][1])/1048576))' 2>/dev/null
echo "  磁盘占用:"
cd /mnt/d/projects/learning/victoriametrics/playground && du -sh data/ 2>/dev/null
echo "  可用内存上限(allowed):"
Q 'vm_allowed_memory_bytes' | python3 -c 'import json,sys
d=json.load(sys.stdin)["data"]["result"]
print("    %.2f MB" % (float(d[0]["value"][1])/1048576))' 2>/dev/null

echo
echo "=============================================="
echo " E7 单节点版本的组件自证"
echo "=============================================="
echo "  -- 单节点版能启动 vminsert/vmselect 吗？--"
docker run --rm --entrypoint /bin/sh victoriametrics/victoria-metrics:latest \
  -c 'ls -la /vminsert /vmselect /vmstorage 2>&1 | head -5; echo "---"; ls / | head -20' 2>&1 | head -20
