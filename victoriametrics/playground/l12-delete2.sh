#!/bin/bash
# 课 12 实验 24：删除的真相 —— 墓碑标记 + 延迟合并（生产必知）
set -u
cd /mnt/d/projects/learning/victoriametrics/playground
VM=http://localhost:8428

echo "===== [1] 删除后磁盘为何反增：观察 data 目录内部结构变化 ====="
echo "-- 当前 data/small 下的 part 数 --"
docker exec vm-learn sh -c "ls /victoria-metrics-data/data/small/2026_09/ 2>/dev/null | wc -l"
echo "-- data 各子目录大小 --"
docker exec vm-learn sh -c "du -sk /victoria-metrics-data/data/* 2>/dev/null"

echo ""
echo "===== [2] 删除是异步的：查相关指标 ====="
echo "-- 查有没有 pending 删除相关的指标 --"
curl -s "$VM/api/v1/query?query=vm_deleted_metrics_total" 2>&1 | head -c 250; echo
curl -s "$VM/api/v1/query?query=vm_pending_deletes" 2>&1 | head -c 250; echo

echo ""
echo "===== [3] 关键实验：删除后等待一段时间，看磁盘是否回落 ====="
echo "-- 先记录当前 --"
DF_A=$(du -sk ./data | awk '{print $1}')
S_A=$(curl -s $VM/api/v1/series/count | python3 -c "import sys,json;print(json.load(sys.stdin)['data'][0])")
echo "  T0:     磁盘=${DF_A}KB 序列=$S_A"
echo "-- 等 20 秒 --"
sleep 20
DF_B=$(du -sk ./data | awk '{print $1}')
S_B=$(curl -s $VM/api/v1/series/count | python3 -c "import sys,json;print(json.load(sys.stdin)['data'][0])")
echo "  T+20s:  磁盘=${DF_B}KB 序列=$S_B"
echo "-- 再等 40 秒 --"
sleep 40
DF_C=$(du -sk ./data | awk '{print $1}')
S_C=$(curl -s $VM/api/v1/series/count | python3 -c "import sys,json;print(json.load(sys.stdin)['data'][0])")
echo "  T+60s:  磁盘=${DF_C}KB 序列=$S_C"
echo "  >> 60 秒内磁盘变化 = $((DF_C-DF_A))KB"

echo ""
echo "===== [4] 删除的数据还能查到吗（不同时间范围） ====="
echo "-- 查已删除的 l12_bigdel，1 小时范围 --"
NOW=$(date +%s)
curl -s --data-urlencode 'query=l12_bigdel' --data-urlencode "start=$((NOW-3600))" --data-urlencode "end=$NOW" --data-urlencode 'step=300' "$VM/api/v1/query_range" \
  | python3 -c "import sys,json;d=json.load(sys.stdin)['data']['result'];print('   query_range(1h) 结果条数 =', len(d))"
echo "-- 用 series API 查 --"
curl -s --data-urlencode 'match[]=l12_bigdel' "$VM/api/v1/series" | head -c 200; echo
echo "-- 指标名清单里还有吗 --"
curl -s "$VM/api/v1/label/__name__/values" | python3 -c "
import sys,json
d=json.load(sys.stdin)['data']
print('   l12_bigdel 在清单中?', 'l12_bigdel' in d)
"

echo ""
echo "===== [5] 删除的不可逆性与备份的关系（本课核心论点） ====="
echo "-- 从刚才的备份恢复，被删的数据能回来吗？ --"
echo "   （l12_backup_vol 里的备份是删除之前做的，理论上包含 l12_highcard）"
docker rm -f vm-delrecover-test > /dev/null 2>&1
docker volume rm l12_delrecover_vol > /dev/null 2>&1
docker volume create l12_delrecover_vol > /dev/null
docker run --rm -v l12_backup_vol:/backup:ro -v l12_delrecover_vol:/victoria-metrics-data \
  victoriametrics/vmrestore:v1.151.0 -src=fs:///backup -storageDataPath=/victoria-metrics-data 2>&1 | grep -E "restored|fatal" | tail -2
docker run -d --name vm-delrecover-test --network vm-cluster-net -p 8457:8428 \
  -v l12_delrecover_vol:/victoria-metrics-data \
  victoriametrics/victoria-metrics:v1.151.0 \
  -storageDataPath=/victoria-metrics-data -httpListenAddr=:8428 -retentionPeriod=30d > /dev/null 2>&1
for i in $(seq 1 25); do
  R=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8457/health 2>/dev/null)
  [ "$R" = "200" ] && break
  sleep 1
done
curl -s -o /dev/null -w "  恢复实例 /health HTTP=%{http_code}\n" http://localhost:8457/health
echo "-- 恢复实例里 l12_highcard 是否还在（已被删的 20000 条） --"
curl -s --data-urlencode 'query=count(l12_highcard)' "http://localhost:8457/api/v1/query" \
  | python3 -c "import sys,json;r=json.load(sys.stdin)['data']['result'];print('   count(l12_highcard) =', r[0]['value'][1] if r else 'NONE')"
