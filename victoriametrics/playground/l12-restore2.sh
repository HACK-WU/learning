#!/bin/bash
# 课 12 实验 7：绕过 fallocate 限制 —— 改用容器内部卷恢复
# 根因：目标目录在 9p(Windows D:\) 挂载上，不支持 fallocate
set -u
cd /mnt/d/projects/learning/victoriametrics/playground
BASE=/mnt/d/projects/learning/victoriametrics/playground

echo "===== [1] 确认：fallocate 在 9p 上不支持，在容器内部卷上支持 ====="
echo "-- 9p 目标（D:\ 挂载） --"
docker run --rm -v $BASE/l12-restore:/t victoriametrics/vmrestore:v1.151.0 \
  sh -c 'dd if=/dev/zero of=/t/l12_falloc.tmp bs=1 count=100 2>/dev/null; fallocate -l 100 /t/l12_falloc.tmp 2>&1 || echo "  fallocate 失败（预计）"' 2>&1 | tail -3
echo "-- 容器内部卷（overlay） --"
docker run --rm victoriametrics/vmrestore:v1.151.0 \
  sh -c 'mkdir -p /tmp/ft && dd if=/dev/zero of=/tmp/ft/a.tmp bs=1 count=100 2>/dev/null; fallocate -l 100 /tmp/ft/a.tmp && echo "  fallocate 成功（overlay 支持）"' 2>&1 | tail -3

echo ""
echo "===== [2] 创建 docker 命名卷（走 overlay，原生支持 fallocate） ====="
docker volume rm l12_restore_vol > /dev/null 2>&1
docker volume create l12_restore_vol
docker volume inspect l12_restore_vol --format '  卷路径={{.Mountpoint}}'

echo ""
echo "===== [3] 备份产物先拷进一个中转目录（方案：备份直接生成在命名卷里） ====="
echo "-- 重新做备份，dst 指向命名卷 --"
docker volume rm l12_backup_vol > /dev/null 2>&1
docker volume create l12_backup_vol
VM=http://localhost:8428
SNAP=$(curl -s "$VM/snapshot/create" | sed -n 's/.*"snapshot":"\([^"]*\)".*/\1/p')
echo "快照名：$SNAP"

docker run --rm \
  -v $BASE/data:/victoria-metrics-data:ro \
  -v l12_backup_vol:/backup \
  victoriametrics/vmbackup:v1.151.0 \
  -storageDataPath=/victoria-metrics-data \
  -snapshotName=$SNAP \
  -dst=fs:///backup 2>&1 | grep -E "backed up|complete|fatal" | tail -5

curl -s "$VM/snapshot/delete?snapshot=$SNAP" > /dev/null

echo ""
echo "===== [4] 在命名卷里执行恢复 ====="
docker run --rm \
  -v l12_backup_vol:/backup:ro \
  -v l12_restore_vol:/victoria-metrics-data \
  victoriametrics/vmrestore:v1.151.0 \
  -src=fs:///backup \
  -storageDataPath=/victoria-metrics-data 2>&1 | grep -E "downloaded|restore|fatal|error" | tail -8

echo ""
echo "===== [5] 用恢复出的数据启动新实例 ====="
docker rm -f vm-restore-test > /dev/null 2>&1
docker run -d --name vm-restore-test --network vm-cluster-net \
  -p 8455:8428 \
  -v l12_restore_vol:/victoria-metrics-data \
  victoriametrics/victoria-metrics:v1.151.0 \
  -storageDataPath=/victoria-metrics-data \
  -httpListenAddr=:8428 \
  -retentionPeriod=30d 2>&1 | tail -1

echo "-- 等待就绪 --"
for i in $(seq 1 30); do
  R=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8455/health 2>/dev/null)
  [ "$R" = "200" ] && break
  sleep 1
done
curl -s -o /dev/null -w "  新实例 /health HTTP=%{http_code}\n" http://localhost:8455/health

echo ""
echo "===== [6] 恢复验证 ====="
echo "-- 恢复后序列总数（源端 41772） --"
curl -s http://localhost:8455/api/v1/series/count; echo
echo "-- 两批 marker --"
for B in before_backup after_backup; do
  curl -s --data-urlencode "query=count(l12_disaster_marker{batch=\"$B\"})" http://localhost:8455/api/v1/query \
    | python3 -c "import sys,json;r=json.load(sys.stdin)['data']['result'];print('  $B =', r[0]['value'][1] if r else 'NONE')"
done
echo "-- 抽查 i=\"7\" 的具体值 --"
curl -s --data-urlencode 'query=l12_disaster_marker{i="7"}' http://localhost:8455/api/v1/query \
  | python3 -c "
import sys,json
for r in json.load(sys.stdin)['data']['result']:
    print('   ', r['metric'].get('batch'), '=', r['value'][1])
" 2>&1 | head -5
echo "-- 指标名清单对照 --"
curl -s "http://localhost:8428/api/v1/label/__name__/values" | python3 -c "import sys,json;print('  源端指标数   =',len(json.load(sys.stdin)['data']))"
curl -s "http://localhost:8455/api/v1/label/__name__/values" | python3 -c "import sys,json;print('  恢复端指标数 =',len(json.load(sys.stdin)['data']))"
