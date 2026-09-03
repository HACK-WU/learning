#!/bin/bash
# 课 12 实验 34：灾难恢复演练 —— RTO / RPO 实测
# 场景：生产实例数据目录被毁，用备份恢复到新实例，测量 RTO 与 RPO
set -u
cd /mnt/d/projects/learning/victoriametrics/playground
BASE=/mnt/d/projects/learning/victoriametrics/playground
VM=http://localhost:8428

echo "===== [1] 模拟生产：建立一个高频写入的实例 ====="
docker rm -f vm-dr-source > /dev/null 2>&1
docker volume rm l12_dr_src_vol > /dev/null 2>&1
docker volume create l12_dr_src_vol > /dev/null
docker run -d --name vm-dr-source --network vm-cluster-net -p 8460:8428 \
  -v l12_dr_src_vol:/victoria-metrics-data \
  victoriametrics/victoria-metrics:v1.151.0 \
  -storageDataPath=/victoria-metrics-data -httpListenAddr=:8428 -retentionPeriod=30d > /dev/null 2>&1
for i in $(seq 1 25); do
  R=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8460/health 2>/dev/null)
  [ "$R" = "200" ] && break
  sleep 1
done
curl -s -o /dev/null -w "  生产实例 /health HTTP=%{http_code}\n" http://localhost:8460/health

echo ""
echo "-- 灌入 5000 条业务数据（模拟历史积累） --"
: > /tmp/l12_dr.txt
NOW=$(date +%s)
for i in $(seq 1 5000); do
  TS=$((NOW - 300 + (i % 300)))
  printf 'l12_biz_metric{job="prod",shard="%s"} %s %s000\n' "$((i % 10))" "$i" "$TS" >> /tmp/l12_dr.txt
done
curl -s -o /dev/null -w "  写入 HTTP=%{http_code}\n" -X POST --data-binary @/tmp/l12_dr.txt "http://localhost:8460/api/v1/import/prometheus"
sleep 3
echo "-- 生产实例序列数 --"
curl -s "http://localhost:8460/api/v1/series/count" | python3 -c "import sys,json;print('  =',json.load(sys.stdin)['data'][0])"

echo ""
echo "===== [2] T0：执行备份（模拟定时备份任务） ====="
docker volume rm l12_dr_backup_vol > /dev/null 2>&1
docker volume create l12_dr_backup_vol > /dev/null
SNAP=$(curl -s "http://localhost:8460/snapshot/create" | sed -n 's/.*"snapshot":"\([^"]*\)".*/\1/p')
echo "  快照 = $SNAP"
docker run --rm -v l12_dr_src_vol:/victoria-metrics-data:ro -v l12_dr_backup_vol:/backup \
  victoriametrics/vmbackup:v1.151.0 \
  -storageDataPath=/victoria-metrics-data -snapshotName=$SNAP -dst=fs:///backup 2>&1 | grep -E "backed up" | tail -2
curl -s "http://localhost:8460/snapshot/delete?snapshot=$SNAP" > /dev/null

echo ""
echo "===== [3] T0 之后继续写入（这部分数据将丢失 = RPO 的度量对象） ====="
: > /tmp/l12_dr2.txt
NOW2=$(date +%s)
for i in $(seq 1 500); do
  printf 'l12_biz_metric{job="prod",shard="%s"} %s %s000\n' "$((i % 10))" "$((i+9000))" "$NOW2" >> /tmp/l12_dr2.txt
done
curl -s -o /dev/null -w "  备份后新写入 500 条 HTTP=%{http_code}\n" -X POST --data-binary @/tmp/l12_dr2.txt "http://localhost:8460/api/v1/import/prometheus"
sleep 2
echo "-- 灾前序列数 --"
curl -s "http://localhost:8460/api/v1/series/count" | python3 -c "import sys,json;print('  =',json.load(sys.stdin)['data'][0])"

echo ""
echo "===== [4] 灾难发生：数据目录被毁（用 docker rm -v 模拟，仅限自建测试实例） ====="
echo "  ⚠️ 安全提示：此操作只删除本次演练自建的 vm-dr-source 容器及其卷，不涉及任何既有数据"
docker rm -f -v vm-dr-source > /dev/null 2>&1
echo "  生产实例已销毁"
docker volume ls | grep l12_dr_src_vol || echo "  数据卷已不存在（灾难成真）"

echo ""
echo "===== [5] 恢复：测量 RTO（从灾难到服务可用的时间） ====="
RTO_START=$(date +%s%N)
docker volume rm l12_dr_restore_vol > /dev/null 2>&1
docker volume create l12_dr_restore_vol > /dev/null
docker run --rm -v l12_dr_backup_vol:/backup:ro -v l12_dr_restore_vol:/victoria-metrics-data \
  victoriametrics/vmrestore:v1.151.0 -src=fs:///backup -storageDataPath=/victoria-metrics-data 2>&1 | grep -E "restored|fatal" | tail -2

docker run -d --name vm-dr-restored --network vm-cluster-net -p 8461:8428 \
  -v l12_dr_restore_vol:/victoria-metrics-data \
  victoriametrics/victoria-metrics:v1.151.0 \
  -storageDataPath=/victoria-metrics-data -httpListenAddr=:8428 -retentionPeriod=30d > /dev/null 2>&1
for i in $(seq 1 40); do
  R=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8461/health 2>/dev/null)
  [ "$R" = "200" ] && break
  sleep 1
done
RTO_END=$(date +%s%N)
RTO_MS=$(( (RTO_END-RTO_START)/1000000 ))
curl -s -o /dev/null -w "  恢复实例 /health HTTP=%{http_code}\n" http://localhost:8461/health
echo "  ** RTO = ${RTO_MS} ms **"

echo ""
echo "===== [6] 测量 RPO：恢复实例丢失了多少数据 ====="
echo "-- 恢复实例序列数 --"
curl -s "http://localhost:8461/api/v1/series/count" | python3 -c "import sys,json;print('  =',json.load(sys.stdin)['data'][0])"
echo "-- 灾前应有 5000+500=5500 条 l12_biz_metric（去重后约 5000 条） --"
curl -s --data-urlencode 'query=count(l12_biz_metric)' "http://localhost:8461/api/v1/query" \
  | python3 -c "import sys,json;r=json.load(sys.stdin)['data']['result'];print('  恢复实例 l12_biz_metric =', r[0]['value'][1] if r else 'NONE')"
echo "-- 检查灾后写入的 500 条（值 9001-9500）是否丢失 --"
curl -s --data-urlencode 'query=count(l12_biz_metric > 9000)' "http://localhost:8461/api/v1/query" \
  | python3 -c "import sys,json;r=json.load(sys.stdin)['data']['result'];print('  值>9000 的条数 =', r[0]['value'][1] if r else 'NONE  ← 这部分就是 RPO 损失')"

echo ""
echo "===== [7] RTO 分解：恢复 vs 启动 ====="
echo "  （恢复+启动总耗时已测：${RTO_MS} ms）"
echo "  -- 单独测恢复耗时 --"
S=$(date +%s%N)
docker volume rm l12_dr_r2_vol > /dev/null 2>&1
docker volume create l12_dr_r2_vol > /dev/null
docker run --rm -v l12_dr_backup_vol:/backup:ro -v l12_dr_r2_vol:/victoria-metrics-data \
  victoriametrics/vmrestore:v1.151.0 -src=fs:///backup -storageDataPath=/victoria-metrics-data 2>&1 | grep -E "restored" | tail -1
E=$(date +%s%N)
echo "  纯 vmrestore 耗时 = $(( (E-S)/1000000 )) ms"
