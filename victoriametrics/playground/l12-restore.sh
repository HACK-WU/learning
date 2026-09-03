#!/bin/bash
# 课 12 实验 6：vmrestore 恢复演练
# 安全方案：恢复到全新目录 l12-restore，用新容器 vm-restore-test 验证
# 绝不删除原始数据目录（已有备份，但保留原环境以便后续课程）
set -u
cd /mnt/d/projects/learning/victoriametrics/playground
BASE=/mnt/d/projects/learning/victoriametrics/playground
VM=http://localhost:8428

echo "===== [1] 恢复前：源端数据指纹 ====="
echo "-- 源序列总数 --"
curl -s $VM/api/v1/series/count; echo
echo "-- 两批 marker 各多少条 --"
curl -s --data-urlencode 'query=count(l12_disaster_marker{batch="before_backup"})' "$VM/api/v1/query" \
  | python3 -c "import sys,json;r=json.load(sys.stdin)['data']['result'];print('  before_backup =', r[0]['value'][1] if r else 'NONE')"
curl -s --data-urlencode 'query=count(l12_disaster_marker{batch="after_backup"})' "$VM/api/v1/query" \
  | python3 -c "import sys,json;r=json.load(sys.stdin)['data']['result'];print('  after_backup  =', r[0]['value'][1] if r else 'NONE')"

echo ""
echo "===== [2] 备份产物确认 ====="
cat $BASE/l12-backup/backup_metadata.ignore; echo
echo "-- backup_complete.ignore 是否存在（恢复前置校验依赖它） --"
ls -la $BASE/l12-backup/backup_complete.ignore

echo ""
echo "===== [3] vmrestore 恢复到全新目录 ====="
docker rm -f vm-restore-test > /dev/null 2>&1
rm -rf $BASE/l12-restore
mkdir -p $BASE/l12-restore
echo "-- 恢复目标目录初始状态 --"
ls -la $BASE/l12-restore | head -5

echo "-- 执行 vmrestore --"
docker run --rm \
  -v $BASE/l12-backup:/backup:ro \
  -v $BASE/l12-restore:/victoria-metrics-data \
  victoriametrics/vmrestore:v1.151.0 \
  -src=fs:///backup \
  -storageDataPath=/victoria-metrics-data 2>&1 | tail -12

echo ""
echo "===== [4] 恢复产物 ====="
echo "-- 恢复目录大小 --"
du -sh $BASE/l12-restore
echo "-- 文件数 --"
find $BASE/l12-restore -type f | wc -l
echo "-- 顶层结构 --"
ls -la $BASE/l12-restore

echo ""
echo "===== [5] 用恢复出的数据启动新实例 ====="
docker run -d --name vm-restore-test --network vm-cluster-net \
  -p 8455:8428 \
  -v $BASE/l12-restore:/victoria-metrics-data \
  victoriametrics/victoria-metrics:v1.151.0 \
  -storageDataPath=/victoria-metrics-data \
  -httpListenAddr=:8428 \
  -retentionPeriod=30d 2>&1 | tail -2

echo "-- 等待就绪 --"
for i in $(seq 1 25); do
  R=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8455/health 2>/dev/null)
  [ "$R" = "200" ] && break
  sleep 1
done
curl -s -o /dev/null -w "  新实例 /health HTTP=%{http_code}\n" http://localhost:8455/health

echo ""
echo "===== [6] 恢复验证：数据是否完整回来了 ====="
echo "-- 恢复后序列总数（源端 41772） --"
curl -s http://localhost:8455/api/v1/series/count; echo
echo "-- 两批 marker 恢复情况 --"
curl -s --data-urlencode 'query=count(l12_disaster_marker{batch="before_backup"})' http://localhost:8455/api/v1/query \
  | python3 -c "import sys,json;r=json.load(sys.stdin)['data']['result'];print('  before_backup =', r[0]['value'][1] if r else 'NONE')"
curl -s --data-urlencode 'query=count(l12_disaster_marker{batch="after_backup"})' http://localhost:8455/api/v1/query \
  | python3 -c "import sys,json;r=json.load(sys.stdin)['data']['result'];print('  after_backup  =', r[0]['value'][1] if r else 'NONE')"
echo "-- 抽查具体值（i=\"7\" 两条） --"
curl -s --data-urlencode 'query=l12_disaster_marker{i="7"}' http://localhost:8455/api/v1/query \
  | python3 -c "
import sys,json
for r in json.load(sys.stdin)['data']['result']:
    print('   ', r['metric'].get('batch'), '=', r['value'][1])
"
echo "-- 恢复实例的自监控是否可用 --"
curl -s 'http://localhost:8455/api/v1/query?query=vm_app_version' | head -c 150; echo

echo ""
echo "===== [7] 关键对照：恢复出来的实例 vs 源实例，指标名清单一致率 ====="
curl -s "$VM/api/v1/label/__name__/values" | python3 -c "import sys,json;print('  源端指标数 =',len(json.load(sys.stdin)['data']))"
curl -s "http://localhost:8455/api/v1/label/__name__/values" | python3 -c "import sys,json;print('  恢复端指标数 =',len(json.load(sys.stdin)['data']))"
