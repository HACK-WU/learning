#!/bin/bash
# 课 12 实验 10：S3 备份正确格式（bucket 与 endpoint 分离）
set -u
cd /mnt/d/projects/learning/victoriametrics/playground
BASE=/mnt/d/projects/learning/victoriametrics/playground
VM=http://localhost:8428
MINIO_IP=$(docker inspect doris-minio --format '{{range $k,$v := .NetworkSettings.Networks}}{{$v.IPAddress}}{{end}}' | head -1)
MINIO_NET=$(docker inspect doris-minio --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{end}}' | head -1)
echo "minio: net=$MINIO_NET ip=$MINIO_IP"

echo ""
echo "===== [1] 用正确格式备份到 S3：s3://<bucket>/<dir> + -customS3Endpoint ====="
SNAP=$(curl -s "$VM/snapshot/create" | sed -n 's/.*"snapshot":"\([^"]*\)".*/\1/p')
echo "快照名：$SNAP"
docker run --rm --network $MINIO_NET \
  -v $BASE/data:/victoria-metrics-data:ro \
  -e AWS_ACCESS_KEY_ID=minioadmin \
  -e AWS_SECRET_ACCESS_KEY=minioadmin \
  victoriametrics/vmbackup:v1.151.0 \
  -storageDataPath=/victoria-metrics-data \
  -snapshotName=$SNAP \
  -dst=s3://vmbackup-l12/full \
  -customS3Endpoint=http://$MINIO_IP:9000 \
  -httpListenAddr=:18430 2>&1 | grep -E "backed up|fatal|error|uploaded" | tail -5
curl -s "$VM/snapshot/delete?snapshot=$SNAP" > /dev/null

echo ""
echo "===== [2] S3 产物核对 ====="
docker run --rm --network $MINIO_NET --entrypoint sh minio/mc:latest -c "
  mc alias set myminio http://$MINIO_IP:9000 minioadmin minioadmin > /dev/null 2>&1
  echo '-- 对象总数 --'
  mc ls --recursive myminio/vmbackup-l12 2>&1 | wc -l
  echo '-- 桶总大小 --'
  mc du myminio/vmbackup-l12 2>&1 | tail -1
  echo '-- 前 6 个对象 --'
  mc ls --recursive myminio/vmbackup-l12 2>&1 | head -6
" 2>&1 | tail -12

echo ""
echo "===== [3] 第二次 S3 备份（观察 server-side copy —— S3 特有优势） ====="
SNAP2=$(curl -s "$VM/snapshot/create" | sed -n 's/.*"snapshot":"\([^"]*\)".*/\1/p')
docker run --rm --network $MINIO_NET \
  -v $BASE/data:/victoria-metrics-data:ro \
  -e AWS_ACCESS_KEY_ID=minioadmin \
  -e AWS_SECRET_ACCESS_KEY=minioadmin \
  victoriametrics/vmbackup:v1.151.0 \
  -storageDataPath=/victoria-metrics-data \
  -snapshotName=$SNAP2 \
  -dst=s3://vmbackup-l12/full \
  -customS3Endpoint=http://$MINIO_IP:9000 \
  -httpListenAddr=:18431 2>&1 | grep -E "backed up|fatal|server-side" | tail -4
curl -s "$VM/snapshot/delete?snapshot=$SNAP2" > /dev/null

echo ""
echo "===== [4] 从 S3 恢复并验证 ====="
docker volume rm l12_s3restore_vol > /dev/null 2>&1
docker volume create l12_s3restore_vol > /dev/null
docker run --rm --network $MINIO_NET \
  -v l12_s3restore_vol:/victoria-metrics-data \
  -e AWS_ACCESS_KEY_ID=minioadmin \
  -e AWS_SECRET_ACCESS_KEY=minioadmin \
  victoriametrics/vmrestore:v1.151.0 \
  -src=s3://vmbackup-l12/full \
  -customS3Endpoint=http://$MINIO_IP:9000 \
  -storageDataPath=/victoria-metrics-data \
  -httpListenAddr=:18432 2>&1 | grep -E "restored|fatal|error" | tail -3

docker rm -f vm-s3restore-test > /dev/null 2>&1
docker run -d --name vm-s3restore-test --network vm-cluster-net \
  -p 8456:8428 \
  -v l12_s3restore_vol:/victoria-metrics-data \
  victoriametrics/victoria-metrics:v1.151.0 \
  -storageDataPath=/victoria-metrics-data -httpListenAddr=:8428 -retentionPeriod=30d > /dev/null 2>&1
for i in $(seq 1 30); do
  R=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8456/health 2>/dev/null)
  [ "$R" = "200" ] && break
  sleep 1
done
curl -s -o /dev/null -w "  /health HTTP=%{http_code}\n" http://localhost:8456/health
echo "-- S3 恢复后序列总数（源端约 41774） --"
curl -s http://localhost:8456/api/v1/series/count; echo
echo "-- 两批 marker 恢复情况 --"
for B in before_backup after_backup; do
  curl -s --data-urlencode "query=count(l12_disaster_marker{batch=\"$B\"})" http://localhost:8456/api/v1/query \
    | python3 -c "import sys,json;r=json.load(sys.stdin)['data']['result'];print('  $B =', r[0]['value'][1] if r else 'NONE')" 2>&1 | head -1
done

echo ""
echo "===== [5] 三种备份目标对照表数据收集 ====="
echo "-- fs 备份大小 --"
docker run --rm -v l12_backup_vol:/backup --entrypoint sh busybox:latest -c 'du -sk /backup' 2>&1 | tail -1
echo "-- S3 备份大小 --"
docker run --rm --network $MINIO_NET --entrypoint sh minio/mc:latest -c "
  mc alias set myminio http://$MINIO_IP:9000 minioadmin minioadmin > /dev/null 2>&1
  mc du myminio/vmbackup-l12 2>&1 | tail -1
" 2>&1 | tail -2
