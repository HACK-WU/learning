#!/bin/bash
# 课 12 实验 8：备份对在线服务的影响 + MinIO(S3) 备份 + 集群版备份差异
set -u
cd /mnt/d/projects/learning/victoriametrics/playground
BASE=/mnt/d/projects/learning/victoriametrics/playground
VM=http://localhost:8428

echo "===== [1] 备份期间写入是否阻塞（生产最关心的问题） ====="
echo "-- 后台启动一次备份 --"
SNAP=$(curl -s "$VM/snapshot/create" | sed -n 's/.*"snapshot":"\([^"]*\)".*/\1/p')
docker run --rm \
  -v $BASE/data:/victoria-metrics-data:ro \
  -v l12_backup_vol:/backup \
  victoriametrics/vmbackup:v1.151.0 \
  -storageDataPath=/victoria-metrics-data \
  -snapshotName=$SNAP \
  -dst=fs:///backup > /tmp/l12_bk.log 2>&1 &
BKP_PID=$!

echo "-- 备份进行中，同时发起 20 次写入，计时 --"
OK=0; FAIL=0
START=$(date +%s%N)
for i in $(seq 1 20); do
  TS=$(date +%s)
  C=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
    --data-binary "l12_bk_concurrent{job=\"l12\",i=\"$i\"} $i ${TS}000" \
    "$VM/api/v1/import/prometheus")
  if [ "$C" = "204" ]; then OK=$((OK+1)); else FAIL=$((FAIL+1)); fi
done
END=$(date +%s%N)
echo "  写入成功 $OK / 失败 $FAIL / 总耗时 $(( (END-START)/1000000 )) ms"
echo "-- 备份进行中，同时查询 --"
curl -s -o /dev/null -w "  查询 HTTP=%{http_code} 耗时=%{time_total}s\n" "$VM/api/v1/query?query=up"
curl -s -o /dev/null -w "  /health HTTP=%{http_code}\n" "$VM/health"

wait $BKP_PID
grep -E "backed up|complete" /tmp/l12_bk.log | tail -2
curl -s "$VM/snapshot/delete?snapshot=$SNAP" > /dev/null

echo ""
echo "===== [2] 关键安全实验：不建快照直接备份会不会出错 ====="
echo "-- 直接对运行中数据目录做备份（无 snapshotName），期望能跑但数据可能不一致 --"
docker run --rm \
  -v $BASE/data:/victoria-metrics-data:ro \
  -v l12_backup_vol:/backup_nosnap \
  victoriametrics/vmbackup:v1.151.0 \
  -storageDataPath=/victoria-metrics-data \
  -dst=fs:///backup_nosnap 2>&1 | grep -E "backed up|fatal|error|snapshot" | tail -5

echo ""
echo "===== [3] MinIO(S3) 备份：配置与执行 ====="
echo "-- 检查 minio 容器与凭据 --"
docker exec doris-minio sh -c 'echo "MINIO_ROOT_USER=$MINIO_ROOT_USER"; echo "MINIO_ROOT_PASSWORD=$MINIO_ROOT_PASSWORD"' 2>&1 | head -3
echo "-- 创建 bucket --"
docker run --rm --network host \
  -e AWS_ACCESS_KEY_ID=minioadmin -e AWS_SECRET_ACCESS_KEY=minioadmin \
  --entrypoint sh victoriametrics/vmbackup:v1.151.0 -c 'echo busybox-no-aws-cli' 2>&1 | tail -1
curl -s -o /dev/null -w "  minio 健康检查 HTTP=%{http_code}\n" http://localhost:9000/minio/health/live

echo "-- 用 mc 客户端建桶 --"
docker run --rm --network host \
  --entrypoint sh minio/mc:latest -c "
    mc alias set myminio http://localhost:9000 minioadmin minioadmin > /dev/null 2>&1 && \
    mc mb myminio/vmbackup-l12 --ignore-existing 2>&1 | tail -2 && \
    mc ls myminio/ 2>&1 | head -5
  " 2>&1 | tail -6

echo ""
echo "===== [4] 往 S3 做一次备份 ====="
SNAP3=$(curl -s "$VM/snapshot/create" | sed -n 's/.*"snapshot":"\([^"]*\)".*/\1/p')
echo "快照名：$SNAP3"
docker run --rm --network host \
  -v $BASE/data:/victoria-metrics-data:ro \
  -e AWS_ACCESS_KEY_ID=minioadmin \
  -e AWS_SECRET_ACCESS_KEY=minioadmin \
  victoriametrics/vmbackup:v1.151.0 \
  -storageDataPath=/victoria-metrics-data \
  -snapshotName=$SNAP3 \
  -dst=s3://http://localhost:9000/vmbackup-l12 \
  -customS3Endpoint=http://localhost:9000 2>&1 | grep -E "backed up|fatal|error|uploaded" | tail -5
curl -s "$VM/snapshot/delete?snapshot=$SNAP3" > /dev/null

echo ""
echo "===== [5] S3 备份产物核对 ====="
docker run --rm --network host \
  --entrypoint sh minio/mc:latest -c "
    mc alias set myminio http://localhost:9000 minioadmin minioadmin > /dev/null 2>&1
    echo '-- 桶内容 --'
    mc ls --recursive myminio/vmbackup-l12 2>&1 | head -5
    echo '-- 对象总数 --'
    mc ls --recursive myminio/vmbackup-l12 2>&1 | wc -l
    echo '-- 桶总大小 --'
    mc du myminio/vmbackup-l12 2>&1 | tail -2
  " 2>&1 | tail -12
