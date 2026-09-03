#!/bin/bash
# 课 12 实验 4：坐实 9p 挂载下快照的空目录假象 + 硬链接直证
# 背景：data 目录是 Windows D:\ 经 9p 挂载，跨目录建硬链接返回不同 inode（9p 假象）
set -u
cd /mnt/d/projects/learning/victoriametrics/playground
VM=http://localhost:8428

echo "===== [1] 9p 挂载的硬链接假象：同目录 vs 跨目录 ====="
docker exec vm-learn sh -c "
  cd /victoria-metrics-data
  rm -f l12_a.txt l12_b.txt
  echo 'x' > l12_a.txt
  echo '-- 同目录硬链接 --'
  ln l12_a.txt l12_b.txt
  stat -c 'l12_a inode=%i links=%h' l12_a.txt
  stat -c 'l12_b inode=%i links=%h' l12_b.txt
  rm -f l12_a.txt l12_b.txt
"
echo
docker exec vm-learn sh -c "
  echo '-- 跨目录硬链接（data/ -> snapshots/ 模拟） --'
  rm -f /victoria-metrics-data/l12_c.txt /victoria-metrics-data/snapshots/l12_d.txt
  echo 'x' > /victoria-metrics-data/l12_c.txt
  ln /victoria-metrics-data/l12_c.txt /victoria-metrics-data/snapshots/l12_d.txt
  stat -c 'l12_c inode=%i links=%h' /victoria-metrics-data/l12_c.txt
  stat -c 'l12_d inode=%i links=%h' /victoria-metrics-data/snapshots/l12_d.txt
  rm -f /victoria-metrics-data/l12_c.txt /victoria-metrics-data/snapshots/l12_d.txt
"

echo ""
echo "===== [2] 快照真实位置：在 data/{small,big,indexdb}/snapshots/ 下 ====="
SNAP=$(curl -s "$VM/snapshot/create" | sed -n 's/.*"snapshot":"\([^"]*\)".*/\1/p')
echo "快照名：$SNAP"
echo "-- data/small/snapshots 下的文件数 --"
docker exec vm-learn sh -c "find /victoria-metrics-data/data/small/snapshots/$SNAP -type f 2>/dev/null | wc -l"
echo "-- data/big/snapshots 下的文件数 --"
docker exec vm-learn sh -c "find /victoria-metrics-data/data/big/snapshots/$SNAP -type f 2>/dev/null | wc -l"
echo "-- data/indexdb/snapshots 下的文件数 --"
docker exec vm-learn sh -c "find /victoria-metrics-data/data/indexdb/snapshots/$SNAP -type f 2>/dev/null | wc -l"
echo "-- 顶层 /snapshots 下的文件数（对照） --"
docker exec vm-learn sh -c "find /victoria-metrics-data/snapshots/$SNAP -type f 2>/dev/null | wc -l"

echo ""
echo "===== [3] 真实硬链接证据：从 data/small/snapshots 取文件反查 ====="
SF=$(docker exec vm-learn sh -c "find /victoria-metrics-data/data/small/snapshots/$SNAP -type f -size +5k 2>/dev/null | head -1")
echo "快照样本文件：$SF"
if [ -n "$SF" ]; then
  echo "-- 快照侧 stat --"
  docker exec vm-learn sh -c "stat -c 'inode=%i links=%h size=%s' '$SF'"
  echo "-- 对应原始 part 路径（把 /snapshots/<SNAP>/ 去掉） --"
  ORIG=$(echo "$SF" | sed "s|/snapshots/$SNAP/|/|")
  echo "原始：$ORIG"
  docker exec vm-learn sh -c "stat -c 'inode=%i links=%h size=%s' '$ORIG' 2>&1"
fi

echo ""
echo "===== [4] 快照的磁盘真实代价：df 前后对比 ====="
echo "-- 删除快照前 df --"
DF1=$(df -k /mnt/d/projects/learning/victoriametrics/playground/data | tail -1 | awk '{print $3}')
echo "已用 1K 块 = $DF1"
curl -s "$VM/snapshot/delete?snapshot=$SNAP" > /dev/null
sleep 2
DF2=$(df -k /mnt/d/projects/learning/victoriametrics/playground/data | tail -1 | awk '{print $3}')
echo "-- 删除快照后 df 已用 1K 块 = $DF2"

echo ""
echo "===== [5] 重新建快照，测 df 增量（这是硬链接零拷贝的直接证据） ====="
DF3=$(df -k /mnt/d/projects/learning/victoriametrics/playground/data | tail -1 | awk '{print $3}')
echo "建前 1K 块 = $DF3"
SNAP2=$(curl -s "$VM/snapshot/create" | sed -n 's/.*"snapshot":"\([^"]*\)".*/\1/p')
sleep 3
DF4=$(df -k /mnt/d/projects/learning/victoriametrics/playground/data | tail -1 | awk '{print $3}')
echo "建后 1K 块 = $DF4"
echo "增量 = $((DF4-DF3)) KB  ← 若接近 0，证明硬链接零拷贝"
echo "快照名2=$SNAP2"
echo "$SNAP2" > /tmp/l12_snap2_name.txt

echo ""
echo "===== [6] 快照后写入新数据，验证快照是冻结视图 ====="
echo "-- 快照元数据文件内容（minTimestamp） --"
docker exec vm-learn sh -c "cat /victoria-metrics-data/snapshots/$SNAP2/metadata/minTimestampForCompositeIndex 2>/dev/null; echo"
echo "-- 记录当前序列数 --"
curl -s $VM/api/v1/series/count; echo
echo "-- 灌入 300 条新序列 --"
for i in $(seq 1 300); do
  printf 'l12_after_snap{job="l12",i="%s"} %s %s000\n' "$i" "$i" "$(date +%s)" >> /tmp/l12_bulk.txt
done
curl -s -o /dev/null -w "  bulk import HTTP=%{http_code}\n" -X POST --data-binary @/tmp/l12_bulk.txt "$VM/api/v1/import/prometheus"
rm -f /tmp/l12_bulk.txt
sleep 3
echo "-- 新序列数 --"
curl -s $VM/api/v1/series/count; echo
echo "-- 快照侧文件是否变化（对比 md5） --"
SF2=$(docker exec vm-learn sh -c "find /victoria-metrics-data/data/small/snapshots/$SNAP2 -type f -size +5k 2>/dev/null | head -1")
if [ -n "$SF2" ]; then
  docker exec vm-learn sh -c "stat -c '快照文件 size=%s links=%h' '$SF2'"
fi
