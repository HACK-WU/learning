#!/bin/bash
# 课 12 实验 9：S3 备份修正版（改用自定义网络 + 固定 httpListenAddr）
set -u
cd /mnt/d/projects/learning/victoriametrics/playground
BASE=/mnt/d/projects/learning/victoriametrics/playground
VM=http://localhost:8428

echo "===== [1] 确认 minio 在哪些 docker 网络上 ====="
docker inspect doris-minio --format '{{range $k,$v := .NetworkSettings.Networks}}网络={{$k}} IP={{$v.IPAddress}}{{"\n"}}{{end}}'

echo ""
echo "===== [2] 用自定义网络连接 minio，避开 host 端口冲突 ====="
SNAP=$(curl -s "$VM/snapshot/create" | sed -n 's/.*"snapshot":"\([^"]*\)".*/\1/p')
echo "快照名：$SNAP"

echo "-- 方法 A：连到 minio 所在网络，用容器名访问 --"
MINIO_NET=$(docker inspect doris-minio --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{end}}' | head -1)
MINIO_IP=$(docker inspect doris-minio --format '{{range $k,$v := .NetworkSettings.Networks}}{{$v.IPAddress}}{{end}}' | head -1)
echo "minio 网络=$MINIO_NET IP=$MINIO_IP"

docker run --rm --network $MINIO_NET \
  -v $BASE/data:/victoria-metrics-data:ro \
  -e AWS_ACCESS_KEY_ID=minioadmin \
  -e AWS_SECRET_ACCESS_KEY=minioadmin \
  victoriametrics/vmbackup:v1.151.0 \
  -storageDataPath=/victoria-metrics-data \
  -snapshotName=$SNAP \
  -dst=s3://http://$MINIO_IP:9000/vmbackup-l12 \
  -customS3Endpoint=http://$MINIO_IP:9000 \
  -httpListenAddr=:18420 2>&1 | grep -E "backed up|fatal|error|uploaded|complete" | tail -6

curl -s "$VM/snapshot/delete?snapshot=$SNAP" > /dev/null

echo ""
echo "===== [3] S3 备份产物核对 ====="
docker run --rm --network $MINIO_NET \
  --entrypoint sh minio/mc:latest -c "
    mc alias set myminio http://$MINIO_IP:9000 minioadmin minioadmin > /dev/null 2>&1
    echo '-- 对象总数 --'
    mc ls --recursive myminio/vmbackup-l12 2>&1 | wc -l
    echo '-- 桶总大小 --'
    mc du myminio/vmbackup-l12 2>&1 | tail -1
    echo '-- 前 8 个对象 --'
    mc ls --recursive myminio/vmbackup-l12 2>&1 | head -8
  " 2>&1 | tail -15

echo ""
echo "===== [4] 关键验证：本地 fs 备份 vs S3 备份，产物是否等价 ====="
echo "-- 本地 fs 备份文件数 --"
docker run --rm -v l12_backup_vol:/backup --entrypoint sh victoriametrics/vmbackup:v1.151.0 \
  -c 'find /backup -type f | wc -l' 2>/dev/null | tail -1
docker run --rm -v l12_backup_vol:/backup --entrypoint sh busybox:latest \
  -c 'find /backup -type f | wc -l' 2>&1 | tail -1

echo ""
echo "===== [5] 增量备份的 server-side copy 能力（fs 不支持，S3 支持） ====="
echo "-- 查看第二次 fs 备份日志里的 server-side copied 字段 --"
grep -h "server-side copied" /tmp/l12_bk.log 2>/dev/null | tail -2
echo "-- 再跑一次 S3 备份，观察是否出现 server-side copy --"
SNAP2=$(curl -s "$VM/snapshot/create" | sed -n 's/.*"snapshot":"\([^"]*\)".*/\1/p')
docker run --rm --network $MINIO_NET \
  -v $BASE/data:/victoria-metrics-data:ro \
  -e AWS_ACCESS_KEY_ID=minioadmin \
  -e AWS_SECRET_ACCESS_KEY=minioadmin \
  victoriametrics/vmbackup:v1.151.0 \
  -storageDataPath=/victoria-metrics-data \
  -snapshotName=$SNAP2 \
  -dst=s3://http://$MINIO_IP:9000/vmbackup-l12 \
  -customS3Endpoint=http://$MINIO_IP:9000 \
  -httpListenAddr=:18421 2>&1 | grep -E "backed up|fatal|server-side" | tail -4
curl -s "$VM/snapshot/delete?snapshot=$SNAP2" > /dev/null

echo ""
echo "===== [6] 从 S3 恢复（验证 S3 备份真的可用） ====="
docker volume rm l12_s3restore_vol > /dev/null 2>&1
docker volume create l12_s3restore_vol > /dev/null
docker run --rm --network $MINIO_NET \
  -v l12_s3restore_vol:/victoria-metrics-data \
  -e AWS_ACCESS_KEY_ID=minioadmin \
  -e AWS_SECRET_ACCESS_KEY=minioadmin \
  victoriametrics/vmrestore:v1.151.0 \
  -src=s3://http://$MINIO_IP:9000/vmbackup-l12 \
  -customS3Endpoint=http://$MINIO_IP:9000 \
  -storageDataPath=/victoria-metrics-data \
  -httpListenAddr=:18422 2>&1 | grep -E "restored|fatal|error" | tail -4

echo "-- 用 S3 恢复的数据启动实例验证 --"
docker rm -f vm-s3restore-test > /dev/null 2>&1
docker run -d --name vm-s3restore-test --network vm-cluster-net \
  -p 8456:8428 \
  -v l12_s3restore_vol:/victoria-metrics-data \
  victoriametrics/victoria-metrics:v1.151.0 \
  -storageDataPath=/victoria-metrics-data -httpListenAddr=:8428 -retentionPeriod=30d > /dev/null 2>&1
for i in $(seq 1 25); do
  R=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8456/health 2>/dev/null)
  [ "$R" = "200" ] && break
  sleep 1
done
curl -s -o /dev/null -w "  /health HTTP=%{http_code}\n" http://localhost:8456/health
echo "-- S3 恢复后序列总数 --"
curl -s http://localhost:8456/api/v1/series/count; echo
