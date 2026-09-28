#!/usr/bin/env bash
LOG=/tmp/bk-lite-install2.log
echo "=== 日志行数: $(wc -l < $LOG) ==="
echo ""
echo "=== 错误/失败 ==="
grep -nE 'ERROR|错误|失败|reset by peer|die |denied' "$LOG" | head -15
echo ""
echo "=== 最后 45 行 ==="
tail -45 "$LOG"
