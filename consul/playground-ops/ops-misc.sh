#!/usr/bin/env bash
BASE=/tmp/consul-ops
export CONSUL_HTTP_ADDR=http://127.0.0.1:8501
SECRET=$(grep 'SecretID' "$BASE/acl/boot.txt" | awk '{print $2}')

echo "===== 1. 优雅下线 leave（与 kill 的区别）====="
PID2=$(pgrep -f 'conf/node2.hcl')
echo "node2 pid=$PID2"
consul leave -http-addr=http://127.0.0.2:8502 -token "$SECRET" 2>&1 || kill -TERM "$PID2"
sleep 5
echo "-- members（left vs failed）--"
consul members -token "$SECRET"

echo
echo "===== 2. 重新加入（复用 data_dir）====="
nohup consul agent -config-file "$BASE/conf/node2.hcl" > "$BASE/log/node2.log" 2>&1 &
sleep 12
consul members -token "$SECRET"

echo
echo "===== 3. 日志：关键运维日志行样例 ====="
echo "-- 选举 --"
grep -h 'elected\|entering leader\|entering follower' "$BASE"/log/node*.log 2>/dev/null | tail -4
echo "-- 成员变更 --"
grep -h 'member.*joined\|member.*left\|Serf.*event' "$BASE"/log/node*.log 2>/dev/null | tail -4
echo "-- raft 相关 --"
grep -h 'raft:' "$BASE"/log/node*.log 2>/dev/null | tail -4

echo
echo "===== 4. 目录与磁盘占用（容量规划用）====="
du -sh "$BASE"/data/node1
echo "-- raft 子目录 --"
du -sh "$BASE"/data/node1/* 2>/dev/null | sort -h
