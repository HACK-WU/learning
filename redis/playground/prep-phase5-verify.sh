#!/bin/bash
# Phase 5 证据核查：验证排障手册里写的每条命令在 Redis 8.10.1 下真的能跑
# 原则：手册只收确定项。命令不存在或报错的，必须改或删。
set -u
R() { redis-cli -p 7201 --user appuser --pass 'AppPass123!' "$@" 2>&1 | head -3; }

echo "===== 症状1：KEYS 阻塞排查相关 ====="
echo -n "  SLOWLOG GET 10      : "; R SLOWLOG GET 10
echo -n "  CLIENT LIST (截断)  : "; R CLIENT LIST | head -c 60; echo
echo -n "  INFO commandstats   : "; R INFO commandstats | grep -c cmdstat_

echo
echo "===== 症状2：内存排查相关 ====="
echo -n "  INFO memory         : "; R INFO memory | grep -m1 used_memory_human
echo -n "  CONFIG GET maxmemory-policy : "; R CONFIG GET maxmemory-policy | tail -1
echo -n "  OBJECT ENCODING     : "; R SET cache:enc:probe a >/dev/null; R OBJECT ENCODING cache:enc:probe
echo -n "  MEMORY USAGE        : "; R MEMORY USAGE cache:enc:probe

echo
echo "===== 症状3：延迟排查相关 ====="
echo -n "  LATENCY LATEST      : "; R LATENCY LATEST
echo -n "  LATENCY HISTORY command : "; R LATENCY HISTORY command
echo -n "  UNLINK 存在性        : "; R UNLINK cache:enc:probe

echo
echo "===== 症状7/8：ACL 相关 ====="
echo -n "  ACL LIST            : "; R ACL LIST | head -c 80; echo
echo -n "  ACL GETUSER appuser : "; R ACL GETUSER appuser | head -c 80; echo
echo -n "  ACL SETUSER 语法     : "; R ACL SETUSER probe_test on '>x' '~cache:*' +get
echo -n "  ACL DELUSER 清理     : "; R ACL DELUSER probe_test
echo -n "  REPLCONF 权限        : "; redis-cli -p 7201 --user replicator --pass 'ReplPass123!' REPLCONF listening-port 7202 2>&1 | head -1
echo -n "  PSYNC 权限(INFO替代) : "; redis-cli -p 7201 --user replicator --pass 'ReplPass123!' INFO replication 2>&1 | head -1

echo
echo "===== 症状9：Lua 相关 ====="
echo -n "  EVAL 简单脚本        : "; R EVAL "return 1+1" 0
echo -n "  SCRIPT KILL 存在性   : "; R SCRIPT KILL

echo
echo "===== 症状11：复制相关 ====="
echo -n "  INFO replication    : "; R INFO replication | grep -m1 role
echo -n "  从库只读验证         : "; redis-cli -p 7202 SET x 1 2>&1 | head -1

echo
echo "===== 通用：redis-cli 工具参数 ====="
echo -n "  --bigkeys 可用性     : "; timeout 20 redis-cli -p 7201 --user appuser --pass 'AppPass123!' --bigkeys 2>&1 | tail -3
echo -n "  --hotkeys 可用性     : "; timeout 20 redis-cli -p 7201 --user appuser --pass 'AppPass123!' --hotkeys 2>&1 | tail -2
