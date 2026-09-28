#!/usr/bin/env bash
echo "=== WSL INTERNAL MEMORY ==="
free -m | sed 's/^/  /'
echo ""
echo "=== SWAP USAGE DETAIL ==="
swapon --show 2>/dev/null | sed 's/^/  /'
echo ""
echo "=== OOM KILLS (dmesg / kernel) ==="
dmesg 2>/dev/null | grep -iE 'oom|killed process|out of memory' | tail -15 | cut -c1-180 | sed 's/^/  /'
echo "  (empty = no dmesg access or no OOM)"
echo ""
echo "=== MEMORY PRESSURE (PSI) ==="
cat /proc/pressure/memory 2>/dev/null | sed 's/^/  /'
echo ""
echo "=== TOP 15 MEM PROCESSES (WSL) ==="
ps aux --sort=-%mem 2>/dev/null | head -16 | awk '{printf "  %-10s %-6s %-6s %s\n", $1, $3, $4, substr($11,1,60)}'
echo ""
echo "=== CGROUP LIMIT ==="
cat /sys/fs/cgroup/memory.max 2>/dev/null | sed 's/^/  /'
cat /sys/fs/cgroup/memory/memory.limit_in_bytes 2>/dev/null | sed 's/^/  /'
