#!/bin/bash
echo "=== PID 982 状态 ==="
docker exec l11 sh -c 'cat /proc/982/status 2>/dev/null | grep -E "^(Name|State|PPid|Pid)"'
echo "=== 尝试 kill -9 982 ==="
docker exec l11 sh -c 'kill -9 982 2>&1; echo "rc=$?"'
sleep 2
docker exec l11 sh -c 'if [ -d /proc/982 ]; then echo "  仍存活"; cat /proc/982/status | grep -E "^(State|PPid)"; else echo "  已死"; fi'
echo "=== 982 的父进程 ==="
docker exec l11 sh -c 'ppid=$(grep PPid /proc/982/status 2>/dev/null | awk "{print \$2}"); echo "PPid=$ppid"; tr "\0" " " < /proc/$ppid/cmdline 2>/dev/null; echo'
