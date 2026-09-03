#!/bin/bash
# 课 12 实验 0：环境探测与数据基线
set -u
cd /mnt/d/projects/learning/victoriametrics/playground

echo "===== [1] vmbackup 镜像是否已有 ====="
docker images --format '{{.Repository}}:{{.Tag}}' | grep -i 'vmbackup' || echo "NONE"

echo ""
echo "===== [2] 尝试拉取 vmbackup:v1.151.0 ====="
timeout 300 docker pull victoriametrics/vmbackup:v1.151.0 2>&1 | tail -5

echo ""
echo "===== [3] 镜像内含哪些二进制 ====="
docker run --rm --entrypoint ls victoriametrics/vmbackup:v1.151.0 /vmbackup-manager 2>&1 | head -3
docker run --rm --entrypoint sh victoriametrics/vmbackup:v1.151.0 -c 'ls /usr/local/bin/ /bin/ 2>/dev/null | head -30' 2>&1 | head -30

echo ""
echo "===== [4] 单节点 vm-learn 数据基线 ====="
echo "-- 版本 --"
curl -s http://localhost:8428/health | head -c 200; echo
curl -s http://localhost:8428/api/v1/query -d 'query=vm_app_version' 2>&1 | head -c 300; echo
echo "-- 序列总数 --"
curl -s http://localhost:8428/api/v1/series/count | head -c 300; echo
echo "-- data 目录（宿主机视角，字节） --"
du -sb ./data 2>/dev/null | tail -2
echo "-- data 顶层结构 --"
ls -la ./data 2>/dev/null | head -20

echo ""
echo "===== [5] minio 可用性（用于 S3 备份实验） ====="
curl -s -o /dev/null -w "minio-9000 HTTP=%{http_code}\n" http://localhost:9000/minio/health/live
