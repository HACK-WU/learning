#!/bin/bash
# 课 12 实验 3：追查「快照几乎为空」与「import 204 却查不到」两个反常
set -u
cd /mnt/d/projects/learning/victoriametrics/playground
VM=http://localhost:8428

echo "===== [A] import 204 却查不到：查自监控计数器 ====="
echo "-- 各 type 的写入行数 --"
curl -s "$VM/api/v1/query?query=vm_rows_inserted_total" \
  | python3 -c "import sys,json; d=json.load(sys.stdin)['data']['result']; [print(r['metric'].get('type'), r['value'][1]) for r in d]" 2>&1 | head -20
echo "-- 序列总数 --"
curl -s $VM/api/v1/series/count; echo
echo "-- 用 /api/v1/labels 看有没有任何 l12_ 前缀 --"
curl -s "$VM/api/v1/label/__name__/values" | python3 -c "import sys,json; d=json.load(sys.stdin)['data']; print('总指标数=',len(d)); print('l12_* =',[x for x in d if x.startswith('l12_')])" 2>&1 | head -5

echo ""
echo "-- 换个思路：用 prometheus remote_write 协议写入 --"
TS=$(date +%s)
printf 'l12_rw_test{job="l12"} 42 %s000\n' "$TS" > /tmp/l12rw.txt
curl -s -o /dev/null -w "  remote_write HTTP=%{http_code}\n" -X POST \
  --data-binary @/tmp/l12rw.txt "$VM/api/v1/write"
sleep 2
curl -s --data-urlencode "query=l12_rw_test" "$VM/api/v1/query" | head -c 250; echo
echo "-- 序列总数（写入后） --"
curl -s $VM/api/v1/series/count; echo

echo ""
echo "-- 容器日志尾部（找 insert 相关报错） --"
docker logs vm-learn --tail 15 2>&1 | tail -15

echo ""
echo "===== [B] 快照为什么几乎为空 ====="
echo "-- 数据目录各子目录大小 --"
docker exec vm-learn sh -c "du -sk /victoria-metrics-data/* 2>/dev/null"
echo "-- data/small 与 data/big 目录内容 --"
docker exec vm-learn sh -c "ls /victoria-metrics-data/data/ 2>&1 | head"
docker exec vm-learn sh -c "ls /victoria-metrics-data/data/small/ 2>&1 | head -10"
echo "-- data/small 下有多少文件 --"
docker exec vm-learn sh -c "find /victoria-metrics-data/data -type f | wc -l"

echo ""
echo "===== [C] 关键测试：该文件系统到底支不支持硬链接 ====="
docker exec vm-learn sh -c "
  cd /victoria-metrics-data
  echo 'hello' > /tmp/l12_hl_src.txt
  cp /tmp/l12_hl_src.txt /victoria-metrics-data/l12_hl_a.txt
  ln /victoria-metrics-data/l12_hl_a.txt /victoria-metrics-data/l12_hl_b.txt 2>&1 && echo 'ln 成功' || echo 'ln 失败'
  stat -c 'a: inode=%i links=%h' /victoria-metrics-data/l12_hl_a.txt
  stat -c 'b: inode=%i links=%h' /victoria-metrics-data/l12_hl_b.txt
  find /victoria-metrics-data -maxdepth 1 -name 'l12_hl_*' | sort
  rm -f /victoria-metrics-data/l12_hl_a.txt /victoria-metrics-data/l12_hl_b.txt
"
echo "-- 文件系统类型 --"
docker exec vm-learn sh -c "df -T /victoria-metrics-data 2>/dev/null | tail -2"
docker exec vm-learn sh -c "mount | grep -i victoria | head -3"

echo ""
echo "===== [D] 再建快照，用多种方式数文件 ====="
SNAP=$(curl -s "$VM/snapshot/create" | sed -n 's/.*"snapshot":"\([^"]*\)".*/\1/p')
echo "快照名：$SNAP"
echo "-- find -type f | wc -l --"
docker exec vm-learn sh -c "find /victoria-metrics-data/snapshots/$SNAP -type f | wc -l"
echo "-- ls -laR | grep ^- | wc -l --"
docker exec vm-learn sh -c "ls -laR /victoria-metrics-data/snapshots/$SNAP | grep '^-' | wc -l"
echo "-- 快照目录树（限制深度 3） --"
docker exec vm-learn sh -c "find /victoria-metrics-data/snapshots/$SNAP -maxdepth 3 | head -25"
echo "-- 容器日志（快照相关） --"
docker logs vm-learn --tail 8 2>&1 | tail -8

echo ""
echo "===== [E] 清理 ====="
curl -s "$VM/snapshot/delete?snapshot=$SNAP"; echo
