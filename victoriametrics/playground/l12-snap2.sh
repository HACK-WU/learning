#!/bin/bash
# 课 12 实验 2：硬链接直证 + 写入排查 + 快照内容清单
set -u
cd /mnt/d/projects/learning/victoriametrics/playground
VM=http://localhost:8428

echo "===== [1] 排查：import 写入为什么查不到 ====="
TS=$(date +%s)
echo "当前 unix 秒=$TS"
echo "-- 路径 A: /api/v1/import/prometheus --"
curl -s -o /dev/null -w "  HTTP=%{http_code}\n" -X POST \
  --data-binary "l12_probe_a{src=\"a\"} 1 ${TS}000" \
  "$VM/api/v1/import/prometheus"
echo "-- 路径 B: /prometheus/api/v1/import/prometheus --"
curl -s -o /dev/null -w "  HTTP=%{http_code}\n" -X POST \
  --data-binary "l12_probe_b{src=\"b\"} 1 ${TS}000" \
  "$VM/prometheus/api/v1/import/prometheus"
echo "-- 路径 C: /api/v1/import --"
curl -s -o /dev/null -w "  HTTP=%{http_code}\n" -X POST \
  --data-binary "l12_probe_c{src=\"c\"} 1 ${TS}000" \
  "$VM/api/v1/import"
sleep 2
echo "-- 立即查三个探针 --"
curl -s --data-urlencode "query=l12_probe_a" "$VM/api/v1/query" | head -c 200; echo
curl -s --data-urlencode "query=l12_probe_b" "$VM/api/v1/query" | head -c 200; echo
curl -s --data-urlencode "query=l12_probe_c" "$VM/api/v1/query" | head -c 200; echo
echo "-- 用 time 参数查（明确时间范围） --"
curl -s --data-urlencode "query=l12_probe_a" --data-urlencode "time=$TS" "$VM/api/v1/query" | head -c 200; echo
echo "-- 查 import 相关自监控指标 --"
curl -s "$VM/api/v1/query?query=vm_rows_inserted_total" | head -c 400; echo

echo ""
echo "===== [2] 新建快照，做硬链接直证 ====="
SNAP=$(curl -s "$VM/snapshot/create" | sed -n 's/.*"snapshot":"\([^"]*\)".*/\1/p')
echo "快照名：$SNAP"

echo "-- 快照内文件总数 --"
docker exec vm-learn sh -c "find /victoria-metrics-data/snapshots/$SNAP -type f | wc -l"
echo "-- 快照内文件清单（前 15 个，带大小） --"
docker exec vm-learn sh -c "find /victoria-metrics-data/snapshots/$SNAP -type f -exec ls -l {} \; | awk '{print \$5, \$9}' | head -15"

echo ""
echo "===== [3] 硬链接直证：同一 inode 出现在两处 ====="
echo "-- 取快照里任意一个 .bin 文件的 inode --"
SNAP_F=$(docker exec vm-learn sh -c "find /victoria-metrics-data/snapshots/$SNAP -type f | head -1")
echo "样本文件：$SNAP_F"
SNAP_INO=$(docker exec vm-learn sh -c "stat -c '%i' '$SNAP_F'")
echo "快照侧 inode=$SNAP_INO"
echo "-- 在原始 data 目录反查该 inode --"
docker exec vm-learn sh -c "find /victoria-metrics-data/data -inum $SNAP_INO"
echo "-- 该文件硬链接数 --"
docker exec vm-learn sh -c "stat -c 'links=%h size=%s' '$SNAP_F'"

echo ""
echo "===== [4] 关键对照：快照后继续写入，原始文件被修改，快照侧是否受影响 ====="
echo "-- 快照前该文件内容 md5 --"
MD1=$(docker exec vm-learn sh -c "md5sum '$SNAP_F' | cut -d' ' -f1")
echo "快照侧 md5(before)=$MD1"
echo "-- 向 VM 灌入一批新数据（触发后台合并/新 part） --"
for i in $(seq 1 200); do
  curl -s -o /dev/null -X POST --data-binary "l12_churn{i=\"$i\"} $((RANDOM % 1000)) $(date +%s)000" "$VM/api/v1/import/prometheus"
done
sleep 5
MD2=$(docker exec vm-learn sh -c "md5sum '$SNAP_F' | cut -d' ' -f1")
echo "快照侧 md5(after)=$MD2"
[ "$MD1" = "$MD2" ] && echo "结论：快照内容未被后续写入改变 ✅（快照是冻结视图）" || echo "结论：快照内容变了 ❌"

echo ""
echo "===== [5] 快照实际磁盘代价：用 stat -c %b 精确算块数 ====="
echo "-- 快照所有文件占用的 512B 块数（硬链接会被重复统计） --"
docker exec vm-learn sh -c "find /victoria-metrics-data/snapshots/$SNAP -type f -printf '%b\n' | awk '{s+=\$1} END {print \"快照总块数=\", s, \"≈\", s*512, \"字节（重复计）\"}'"
echo "-- 原始 data 目录块数 --"
docker exec vm-learn sh -c "find /victoria-metrics-data/data -type f -printf '%b\n' | awk '{s+=\$1} END {print \"原始总块数=\", s, \"≈\", s*512, \"字节\"}'"

echo ""
echo "===== [6] 清理 ====="
curl -s "$VM/snapshot/delete?snapshot=$SNAP"; echo
