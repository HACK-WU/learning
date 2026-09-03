#!/bin/bash
# 课 12 实验 5：vmbackup 全量备份 + 增量备份 + 恢复（灾难恢复演练）
# 危险提示：rm -rf 仅限 playground/l12-backup 与 l12-restore 两个自建目录
set -u
cd /mnt/d/projects/learning/victoriametrics/playground
VM=http://localhost:8428
BASE=/mnt/d/projects/learning/victoriametrics/playground

rm -rf $BASE/l12-backup $BASE/l12-restore
mkdir -p $BASE/l12-backup $BASE/l12-restore

echo "===== [1] 制造可辨识的数据标记 ====="
TS=$(date +%s)
{
  for i in $(seq 1 50); do
    printf 'l12_disaster_marker{job="l12",batch="before_backup",i="%s"} %s %s000\n' "$i" "$i" "$TS"
  done
} > /tmp/l12_marker.txt
curl -s -o /dev/null -w "  写入 50 条标记 HTTP=%{http_code}\n" -X POST --data-binary @/tmp/l12_marker.txt "$VM/api/v1/import/prometheus"
sleep 3
echo "-- 备份前序列总数 --"
curl -s $VM/api/v1/series/count; echo
echo "-- 备份前 marker 可查 --"
curl -s --data-urlencode 'query=count(l12_disaster_marker)' "$VM/api/v1/query" | python3 -c "import sys,json;print('  marker 序列数 =', json.load(sys.stdin)['data']['result'][0]['value'][1])" 2>&1 | head -2

echo ""
echo "===== [2] 全量备份（vmbackup，直挂宿主机目录，走 snapshot 服务） ====="
SNAP=$(curl -s "$VM/snapshot/create" | sed -n 's/.*"snapshot":"\([^"]*\)".*/\1/p')
echo "快照名：$SNAP"
echo "-- 备份耗时与产物 --"
time docker run --rm \
  -v $BASE/data:/victoria-metrics-data:ro \
  -v $BASE/l12-backup:/backup \
  victoriametrics/vmbackup:v1.151.0 \
  -storageDataPath=/victoria-metrics-data \
  -snapshotName=$SNAP \
  -dst=fs:///backup 2>&1 | tail -20

echo ""
echo "===== [3] 备份产物结构 ====="
echo "-- 备份总大小 --"
du -sh $BASE/l12-backup
echo "-- 文件数 --"
find $BASE/l12-backup -type f | wc -l
echo "-- 顶层目录 --"
ls -la $BASE/l12-backup | head -20

echo ""
echo "===== [4] 增量备份：灌入新数据后再备一次 ====="
TS2=$(date +%s)
{
  for i in $(seq 1 50); do
    printf 'l12_disaster_marker{job="l12",batch="after_backup",i="%s"} %s %s000\n' "$i" "$i" "$TS2"
  done
} > /tmp/l12_marker2.txt
curl -s -o /dev/null -w "  写入 50 条第二批标记 HTTP=%{http_code}\n" -X POST --data-binary @/tmp/l12_marker2.txt "$VM/api/v1/import/prometheus"
sleep 3
echo "-- 新序列总数 --"
curl -s $VM/api/v1/series/count; echo

SNAP2=$(curl -s "$VM/snapshot/create" | sed -n 's/.*"snapshot":"\([^"]*\)".*/\1/p')
echo "快照名2：$SNAP2"
echo "-- 第二次备份（同一 dst，形成增量） --"
time docker run --rm \
  -v $BASE/data:/victoria-metrics-data:ro \
  -v $BASE/l12-backup:/backup \
  victoriametrics/vmbackup:v1.151.0 \
  -storageDataPath=/victoria-metrics-data \
  -snapshotName=$SNAP2 \
  -dst=fs:///backup 2>&1 | tail -15

echo ""
echo "===== [5] 增量效果：备份目录大小与文件数变化 ====="
echo "-- 第二次备份后总大小 --"
du -sh $BASE/l12-backup
echo "-- 文件数 --"
find $BASE/l12-backup -type f | wc -l
echo "-- 备份目录结构（前 25 项） --"
find $BASE/l12-backup -maxdepth 3 | head -25

echo ""
echo "===== [6] 删除刚建的两个快照 ====="
curl -s "$VM/snapshot/delete?snapshot=$SNAP"; echo
curl -s "$VM/snapshot/delete?snapshot=$SNAP2"; echo
