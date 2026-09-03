#!/bin/bash
# 课 12 实验 1：快照机制 —— 硬链接、零拷贝、空间占用真相
# 危险提示：涉及 rm -rf 的均限定在 playground/l12-* 目录内，绝不触碰 ./data
set -u
cd /mnt/d/projects/learning/victoriametrics/playground

VM=http://localhost:8428
DATA_HOST=/mnt/d/projects/learning/victoriametrics/playground/data

echo "===== [1] 挂载确认（容器内数据路径） ====="
docker inspect vm-learn --format '{{range .Mounts}}{{.Source}} -> {{.Destination}}{{"\n"}}{{end}}'

echo ""
echo "===== [2] 快照前：磁盘占用 / 序列数 / inode 基数 ====="
echo "-- 宿主机 du -sb（字节） --"
du -sb $DATA_HOST | tail -1
echo "-- 真实磁盘占用 df（1K 块） --"
df -k $DATA_HOST | tail -1
echo "-- 序列数 --"
curl -s $VM/api/v1/series/count; echo
echo "-- snapshots 目录现状 --"
docker exec vm-learn ls -la /victoria-metrics-data/snapshots 2>&1 | head -10

echo ""
echo "===== [3] 创建快照 ====="
SNAP_JSON=$(curl -s "$VM/snapshot/create")
echo "返回：$SNAP_JSON"
SNAP_NAME=$(echo "$SNAP_JSON" | sed -n 's/.*"snapshot":"\([^"]*\)".*/\1/p')
echo "快照名：$SNAP_NAME"

echo ""
echo "===== [4] 快照后：磁盘占用对比（验证硬链接不占空间） ====="
sleep 2
echo "-- 宿主机 du -sb（会变大，因为 du 把硬链接重复计） --"
du -sb $DATA_HOST | tail -1
echo "-- 真实磁盘占用 df（1K 块）—— 关键：这个不应显著变化 --"
df -k $DATA_HOST | tail -1

echo ""
echo "===== [5] 快照目录结构 ====="
docker exec vm-learn sh -c "ls -la /victoria-metrics-data/snapshots/ | head -5"
echo "-- 快照内第一层 --"
docker exec vm-learn sh -c "ls /victoria-metrics-data/snapshots/$SNAP_NAME/ | head -10"
echo "-- 快照总大小（docker exec du） --"
docker exec vm-learn sh -c "du -sh /victoria-metrics-data/snapshots/$SNAP_NAME"

echo ""
echo "===== [6] 硬链接证据：快照文件与原始数据 inode 相同 ====="
echo "-- 找一个快照里的真实数据文件 --"
SFILE=$(docker exec vm-learn sh -c "find /victoria-metrics-data/snapshots/$SNAP_NAME -name '*.bin' -size +10k | head -1")
echo "样本文件：$SFILE"
docker exec vm-learn sh -c "stat -c 'inode=%i links=%h size=%s %n' '$SFILE'"
echo "-- 反查原始数据目录同 inode 的文件（links>=2 证明硬链接） --"
docker exec vm-learn sh -c "find /victoria-metrics-data/data -name '*.bin' -size +10k -exec stat -c '%i %h %n' {} \; | head -5"

echo ""
echo "===== [7] 快照期间写入是否阻塞 ====="
TS=$(date +%s)
curl -s -o /dev/null -w "写入 HTTP=%{http_code}\n" -X POST \
  --data-binary "l12_snapshot_write_test{stage=\"snap\"} 1 ${TS}000" \
  "$VM/api/v1/import/prometheus"
sleep 2
curl -s "$VM/api/v1/query?query=l12_snapshot_write_test" | head -c 200; echo

echo ""
echo "===== [8] 快照列表与删除 ====="
curl -s "$VM/snapshot/list" | head -c 300; echo
echo "-- 删除该快照 --"
curl -s "$VM/snapshot/delete?snapshot=$SNAP_NAME" ; echo
echo "-- 删除后 du --"
du -sb $DATA_HOST | tail -1
echo "-- 删除后 snapshots 目录 --"
docker exec vm-learn sh -c "ls -la /victoria-metrics-data/snapshots/"
