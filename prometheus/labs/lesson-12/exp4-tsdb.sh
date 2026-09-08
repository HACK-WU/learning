#!/usr/bin/env bash
D=/mnt/d/projects/learning/prometheus/labs/lesson-12

echo "===== [1] 当前 TSDB 状态 ====="
curl -s http://localhost:19500/api/v1/status/tsdb 2>&1 | python3 -c "
import json,sys
d=json.load(sys.stdin)['data']
print('headSeries        :', d.get('headStats',{}).get('numSeries'))
print('numLabelPairs     :', d.get('headStats',{}).get('numLabelPairs'))
print('chunkCount        :', d.get('headStats',{}).get('chunkCount'))
print('minTime/maxTime   :', d.get('headStats',{}).get('minTime'), d.get('headStats',{}).get('maxTime'))
print('seriesCountByMetricName top5:', sorted(d.get('seriesCountByMetricName',[]), key=lambda x:-x['value'])[:5])
" 2>&1

echo
echo "===== [2] admin API 未开启时会怎样（对照） ====="
echo "（本实例已用 --web.enable-admin-api 启动，此处仅为说明）"

echo
echo "===== [3] 快照 snapshot ====="
SNAP=$(curl -s -XPOST http://localhost:19500/api/v1/admin/tsdb/snapshot)
echo "$SNAP" | head -c 400; echo
SNAPNAME=$(echo "$SNAP" | python3 -c "import json,sys; print(json.load(sys.stdin)['data']['name'])" 2>/dev/null)
echo "snapshot name = $SNAPNAME"

echo
echo "===== [4] 快照落盘位置与大小 ====="
docker exec l12-prom sh -c "ls -d /prometheus/snapshots/$SNAPNAME 2>&1; du -sh /prometheus/snapshots/$SNAPNAME 2>&1"
echo "--- 快照内容（block 目录） ---"
docker exec l12-prom sh -c "ls /prometheus/snapshots/$SNAPNAME 2>&1 | head"
