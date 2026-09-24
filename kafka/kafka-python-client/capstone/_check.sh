#!/bin/bash
echo "=== 所有含 app.main 的进程（含父子关系）==="
docker exec l11 sh -c 'for p in $(ls /proc | grep -E "^[0-9]+$"); do
  [ -r /proc/$p/cmdline ] || continue
  c=$(tr "\0" " " < /proc/$p/cmdline 2>/dev/null)
  case "$c" in
    *app.main:app*) 
      ppid=$(grep -i "^PPid" /proc/$p/status 2>/dev/null | awk "{print \$2}")
      echo "  PID=$p PPid=$ppid  $(echo $c | cut -c1-70)";;
  esac
done'
echo
echo "=== 监听 8000 的进程 ==="
docker exec l11 sh -c 'cat /proc/net/tcp 2>/dev/null | awk "NR>1{print \$2}" | grep -i ":1F90" | head -3'
echo "  (1F90 hex = 8000)"
