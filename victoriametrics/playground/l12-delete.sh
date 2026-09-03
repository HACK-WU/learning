#!/bin/bash
# 课 12 实验 22：深挖删除 API（生产高危）+ 排查查询返 NONE
set -u
cd /mnt/d/projects/learning/victoriametrics/playground
VM=http://localhost:8428

echo "===== [1] 重大发现复核：VM 的 delete_series 真的能删数据 ====="
echo "-- 写入 100 条可辨识数据 --"
: > /tmp/l12_del.txt
for i in $(seq 1 100); do
  printf 'l12_del_target{job="l12",i="%s"} %s %s000\n' "$i" "$i" "$(date +%s)" >> /tmp/l12_del.txt
done
curl -s -o /dev/null -w "  写入 HTTP=%{http_code}\n" -X POST --data-binary @/tmp/l12_del.txt "$VM/api/v1/import/prometheus"
sleep 3
echo "-- 删除前 --"
curl -s --data-urlencode 'query=count(l12_del_target)' "$VM/api/v1/query" \
  | python3 -c "import sys,json;r=json.load(sys.stdin)['data']['result'];print('   count =', r[0]['value'][1] if r else 'NONE')"

echo "-- 执行删除 --"
curl -s -o /dev/null -w "   delete_series HTTP=%{http_code}\n" \
  -X POST "$VM/api/v1/admin/tsdb/delete_series" --data-urlencode 'match[]=l12_del_target'
sleep 3
echo "-- 删除后立即查 --"
curl -s --data-urlencode 'query=count(l12_del_target)' "$VM/api/v1/query" \
  | python3 -c "import sys,json;r=json.load(sys.stdin)['data']['result'];print('   count =', r[0]['value'][1] if r else 'NONE')"
echo "-- 序列总数（看是否真的从存储里消失） --"
curl -s $VM/api/v1/series/count; echo

echo ""
echo "===== [2] 关键：删除是「立即生效」还是「延迟生效」 ====="
echo "-- 官方文档说删除是异步的，需要 -deleteDelay。查当前 deleteDelay --"
docker logs vm-learn --tail 30 2>&1 | grep -iE "delete|tombstone" | tail -5
echo "-- 再写 50 条，观察删除是否还在后台生效 --"
: > /tmp/l12_del2.txt
for i in $(seq 1 50); do
  printf 'l12_del_target{job="l12",i="n%s"} %s %s000\n' "$i" "$i" "$(date +%s)" >> /tmp/l12_del2.txt
done
curl -s -o /dev/null -X POST --data-binary @/tmp/l12_del2.txt "$VM/api/v1/import/prometheus"
sleep 3
curl -s --data-urlencode 'query=count(l12_del_target)' "$VM/api/v1/query" \
  | python3 -c "import sys,json;r=json.load(sys.stdin)['data']['result'];print('   新写 50 条后 count =', r[0]['value'][1] if r else 'NONE')"

echo ""
echo "===== [3] 排查：为什么 l12_dup / l12_manylabels 查不到 ====="
echo "-- 用 series API 查（绕过 query 的 staleness/lookback） --"
curl -s --data-urlencode 'match[]=l12_dup' "$VM/api/v1/series" | head -c 300; echo
curl -s --data-urlencode 'match[]=l12_manylabels' "$VM/api/v1/series" | head -c 300; echo
echo "-- 用时间范围查询（明确 start/end） --"
NOW=$(date +%s)
curl -s --data-urlencode 'query=l12_manylabels' --data-urlencode "start=$((NOW-3600))" --data-urlencode "end=$NOW" --data-urlencode 'step=60' "$VM/api/v1/query_range" \
  | python3 -c "import sys,json;d=json.load(sys.stdin)['data']['result'];print('   query_range 结果条数 =', len(d))" 2>&1 | head -2
echo "-- 检查指标名是否真的进去了 --"
curl -s "$VM/api/v1/label/__name__/values" | python3 -c "
import sys,json
d=json.load(sys.stdin)['data']
for n in ['l12_dup','l12_manylabels','l12_del_target','l12_highcard']:
    print('   ', n, '在指标名清单中?', n in d)
"

echo ""
echo "===== [4] l12_highcard 被删了吗（上面误删的后果） ====="
curl -s "$VM/api/v1/label/__name__/values" | python3 -c "
import sys,json
d=json.load(sys.stdin)['data']
print('   l12_highcard 还在?', 'l12_highcard' in d)
print('   总指标名数 =', len(d))
"

echo ""
echo "===== [5] 关键生产问题：删除的代价（重建索引 / 磁盘空间是否释放） ====="
echo "-- 删除前后磁盘占用 --"
du -sk ./data | tail -1
echo "-- 删除后序列总数 --"
curl -s $VM/api/v1/series/count; echo

echo ""
echo "===== [6] 保留期参数（status/flags 失败，改用其他方式） ====="
curl -s "$VM/api/v1/status/flags" | head -c 200; echo
echo "-- 从容器启动命令读 --"
docker inspect vm-learn --format '{{range .Args}}{{.}}{{"\n"}}{{end}}' 2>/dev/null | grep -iE "retention|dedup|maxLabels" | head -5
